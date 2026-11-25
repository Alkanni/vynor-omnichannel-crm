require 'rails_helper'

RSpec.describe AiAgents::ActionSchema do
  include_context 'with active record encryption'

  let(:ai_agent) { create(:ai_agent) }
  let(:schema) { described_class.new(ai_agent: ai_agent, written_rows: [['Ani', '', '1 Oktober']]) }

  context 'with a writable Google Sheets integration' do
    before { create(:ai_agent_integration, ai_agent: ai_agent) }

    it 'asks for a row with one field per named column and lists the rows already written' do
      properties = schema.json_schema('ai_agent_reply')[:schema][:properties]

      expect(properties[:write_sheet_row]).to eq(type: 'boolean')
      expect(properties[:sheet_row]).to eq(type: 'object', properties: { 'Nama' => { type: 'string' }, 'Tanggal' => { type: 'string' } },
                                           required: %w[Nama Tanggal], additionalProperties: false)
      expect(schema.instructions).to include('Saat customer sudah mengisi format booking lengkap', 'Columns: Nama, Tanggal',
                                             '["Ani","","1 Oktober"]')
    end

    it 'returns the row in header order, with blanks for unnamed columns, only when asked to write' do
      expect(schema.parse('write_sheet_row' => true, 'sheet_row' => { 'Tanggal' => ' 24 Oktober ', 'Nama' => 'Budi' })[:sheet_row])
        .to eq(['Budi', '', '24 Oktober'])
      expect(schema.parse('write_sheet_row' => false, 'sheet_row' => { 'Nama' => 'Budi', 'Tanggal' => '' })[:sheet_row]).to be_nil
      expect(schema.parse('write_sheet_row' => true, 'sheet_row' => { 'Nama' => '', 'Tanggal' => '' })[:sheet_row]).to be_nil
    end
  end

  it 'leaves the sheet out when the integration cannot write' do
    create(:ai_agent_integration, ai_agent: ai_agent, status: :needs_reconnect)

    expect(schema).not_to be_any
    expect(schema.parse('write_sheet_row' => true, 'sheet_row' => { 'Nama' => 'Budi' })[:sheet_row]).to be_nil
  end

  describe 'bookings' do
    let(:label) { create(:label, account: ai_agent.account, title: 'booking') }
    let(:held) { create(:booking, account: ai_agent.account, scheduled_at: Time.utc(2026, 11, 20, 3, 0)) }
    let(:schema) { described_class.new(ai_agent: ai_agent, bookings: [held]) }
    let(:booking) do
      { 'customer_name' => ' Budi ', 'service' => 'Cuci salon', 'date' => '2026-11-21', 'time' => '9:30', 'notes' => '', 'Plat nomor' => 'B 1234 CD' }
    end

    before do
      ai_agent.update!(booking_enabled: true, booking_conditions: 'Saat customer ingin datang ke bengkel.', booking_label_id: label.id,
                       booking_fields: ['Plat nomor'])
    end

    context 'with the bookings feature' do
      # The bookings above are on 2026-11-21, after this time.
      before do
        ai_agent.account.enable_features!('bookings')
        travel_to(Time.utc(2026, 11, 19, 3, 0))
      end

      it 'asks for the core and the agent fields, with the condition, the bookings held, and the calendar' do
        properties = schema.json_schema('ai_agent_reply')[:schema][:properties]
        fields = %w[customer_name service date time notes replaces_booking] + ['Plat nomor']

        expect(properties[:create_booking]).to eq(type: 'boolean')
        expect(properties[:booking]).to eq(type: 'object', properties: fields.index_with { { type: 'string' } }, required: fields,
                                           additionalProperties: false)
        expect(properties[:cancel_booking]).to eq(type: 'string')
        expect(schema.instructions).to include(described_class::BOOKING_INSTRUCTIONS, described_class::HELD_BOOKING_INSTRUCTIONS,
                                               'Saat customer ingin datang ke bengkel.',
                                               "Bookings already in this conversation:\n##{held.id} Cuci salon, 2026-11-20 10:00, requested")
        travel_to(Time.utc(2026, 11, 19, 3, 0)) do
          expect(schema.calendar).to start_with('Calendar: Thursday 2026-11-19 (today), Friday 2026-11-20 (tomorrow), ' \
                                                'Saturday 2026-11-21 (the day after tomorrow), Sunday 2026-11-22,')
          expect(schema.calendar).to end_with('Thursday 2026-12-03')
        end
      end

      it 'gives the reply check the calendar, the condition, the bookings held, and the time the reply fills in the booking' do
        travel_to(Time.utc(2026, 11, 19, 3, 0)) do
          known = "#{schema.calendar}\nSaat customer ingin datang ke bengkel.\n##{held.id} Cuci salon, 2026-11-20 10:00, requested"

          expect(schema.known_text('booking' => booking)).to eq("#{known}\n09:30")
          expect(schema.known_text('booking' => booking.merge('time' => 'pagi'))).to eq(known)
        end
      end

      it 'returns the booking at its time in the agent time zone, with the agent fields as details' do
        expect(schema.parse('create_booking' => true, 'booking' => booking)).to include(
          booking: { service: 'Cuci salon', customer_name: 'Budi', scheduled_at: Time.utc(2026, 11, 21, 2, 30), notes: nil,
                     details: { 'Plat nomor' => 'B 1234 CD' }, rescheduled_from_id: nil },
          booking_rejection: nil, booking_cancellation: nil
        )
      end

      it 'links a booking to the one it replaces, only when the customer still has that one' do
        [held.id.to_s, "##{held.id}"].each do |number|
          expect(schema.parse('create_booking' => true, 'booking' => booking.merge('replaces_booking' => number))[:booking])
            .to include(rescheduled_from_id: held.id), number
        end
        other = create(:booking, account: ai_agent.account)
        [other.id.to_s, '999999', 'besok'].each do |number|
          expect(schema.parse('create_booking' => true, 'booking' => booking.merge('replaces_booking' => number))[:booking])
            .to include(rescheduled_from_id: nil), number
        end
      end

      it 'returns the booking the customer asked to cancel, among the ones they still have' do
        expect(schema.parse('create_booking' => false, 'cancel_booking' => held.id.to_s)).to include(booking: nil, booking_cancellation: held.id)
        expect(schema.parse('create_booking' => false, 'cancel_booking' => '')).to include(booking_cancellation: nil)
        expect(schema.parse('create_booking' => false, 'cancel_booking' => create(:booking).id.to_s)).to include(booking_cancellation: nil)
      end

      it 'asks for the booking to replace or cancel only when the conversation still has one' do
        schema = described_class.new(ai_agent: ai_agent, bookings: [])
        properties = schema.json_schema('ai_agent_reply')[:schema][:properties]

        expect(properties[:booking][:required]).to eq(%w[customer_name service date time notes] + ['Plat nomor'])
        expect(properties).not_to have_key(:cancel_booking)
        expect(schema.instructions).not_to include(described_class::HELD_BOOKING_INSTRUCTIONS)
        expect(described_class::HELD_BOOKING_INSTRUCTIONS.squish).to include('which you never mention to the customer')
      end

      it 'returns neither a booking nor a rejection unless a booking is asked for' do
        expect(schema.parse('create_booking' => false, 'booking' => booking)).to include(booking: nil, booking_rejection: nil)
        expect(schema.parse('create_booking' => 'true', 'booking' => booking)).to include(booking: nil, booking_rejection: nil)
      end

      it 'returns why a booking asked for without a date and time that parse, or without a service, cannot be one' do
        [{ 'date' => '2026-02-30' }, { 'date' => 'besok' }, { 'time' => '24:00' }, { 'time' => 'pagi' }].each do |change|
          expect(schema.parse('create_booking' => true, 'booking' => booking.merge(change)))
            .to include(booking: nil, booking_rejection: :invalid_schedule), change.inspect
        end
        expect(schema.parse('create_booking' => true, 'booking' => 'Cuci salon besok jam 9.30'))
          .to include(booking: nil, booking_rejection: :invalid_schedule)
        expect(schema.parse('create_booking' => true, 'booking' => booking.merge('service' => ' ')))
          .to include(booking: nil, booking_rejection: :missing_service)
      end

      it 'returns why a booking at a time that has passed cannot be one' do
        travel_to(Time.utc(2026, 11, 20, 3, 0)) do # 10:00 in Asia/Jakarta
          [%w[2026-11-20 09:00], %w[2026-11-20 10:00], %w[2026-11-19 23:00]].each do |date, time|
            expect(schema.parse('create_booking' => true, 'booking' => booking.merge('date' => date, 'time' => time)))
              .to include(booking: nil, booking_rejection: :past_schedule), "#{date} #{time}"
          end
          expect(schema.parse('create_booking' => true, 'booking' => booking.merge('date' => '2026-11-20', 'time' => '10:30'))[:booking])
            .to include(scheduled_at: Time.utc(2026, 11, 20, 3, 30))
        end
      end

      it 'compares a booking with the current time in the time zone of the agent' do
        values = booking.merge('date' => '2026-11-20', 'time' => '23:00')

        travel_to(Time.utc(2026, 11, 20, 14, 30)) do
          expect(schema.parse('create_booking' => true, 'booking' => values)[:booking]).to include(scheduled_at: Time.utc(2026, 11, 20, 16, 0))

          ai_agent.update!(timezone: 'Asia/Jayapura')
          expect(schema.parse('create_booking' => true, 'booking' => values)).to include(booking: nil, booking_rejection: :past_schedule)
        end
      end

      it 'returns a booking without a name, which the conversation contact fills in' do
        expect(schema.parse('create_booking' => true, 'booking' => booking.merge('customer_name' => ' ')))
          .to include(booking: hash_including(service: 'Cuci salon', customer_name: ''), booking_rejection: nil)
      end

      it 'asks the model for the customer name when the conversation does not give it' do
        expect(described_class::BOOKING_INSTRUCTIONS.squish)
          .to end_with("Before the summary, ask for the customer's name when the conversation does not give it.")
      end

      it 'counts as an action on its own' do
        expect(schema).to be_any
      end

      it 'starts the calendar on the date in the agent time zone' do
        travel_to(Time.utc(2026, 11, 19, 18, 0)) do
          expect(schema.calendar).to start_with('Calendar: Friday 2026-11-20 (today), Saturday 2026-11-21 (tomorrow),')
        end
      end

      it 'reads the time in the time zone of the agent, with or without a leading zero' do
        ai_agent.update!(timezone: 'Asia/Makassar')

        ['9:30', '09:30'].each do |time|
          expect(schema.parse('create_booking' => true, 'booking' => booking.merge('time' => time))[:booking])
            .to include(scheduled_at: Time.utc(2026, 11, 21, 1, 30))
        end
      end

      it 'keeps an agent field the model left out as blank, and the notes it filled in' do
        values = booking.except('Plat nomor').merge('notes' => ' Bawa STNK ')

        expect(schema.parse('create_booking' => true, 'booking' => values)[:booking])
          .to include(notes: 'Bawa STNK', details: { 'Plat nomor' => '' })
      end

      it 'says none when the conversation has no bookings yet' do
        expect(described_class.new(ai_agent: ai_agent).instructions).to include("Bookings already in this conversation:\nnone")
      end

      it 'gives a reply of an agent without a summary template the same schema and instructions as any other' do
        reply_schema = described_class.new(ai_agent: ai_agent, bookings: [held], reply: true)

        expect(reply_schema.json_schema('ai_agent_reply')).to eq(schema.json_schema('ai_agent_reply'))
        expect(reply_schema.instructions).to eq(schema.instructions)
        expect(reply_schema.summary_request('show_booking_summary' => true, 'booking' => booking)).to eq(booking: nil, booking_rejection: nil)
      end

      context 'with a booking summary template' do
        let(:reply_schema) { described_class.new(ai_agent: ai_agent, bookings: [held], reply: true) }

        before { ai_agent.update!(booking_summary_template: 'Ringkasan: {{booking.service}}') }

        it 'asks a reply whether it shows the summary, after the booking instructions and before the condition' do
          expect(reply_schema.json_schema('ai_agent_reply')[:schema][:properties][:show_booking_summary]).to eq(type: 'boolean')
          expect(reply_schema.instructions).to include(
            "#{described_class::HELD_BOOKING_INSTRUCTIONS}#{AiAgents::BookingSummary::INSTRUCTIONS}Condition:\nSaat customer ingin datang"
          )
        end

        it 'leaves the summary out of a schema that is not a reply\'s, such as the Watcher\'s' do
          expect(schema.json_schema('ai_agent_watch')[:schema][:properties]).not_to have_key(:show_booking_summary)
          expect(schema.instructions).not_to include(AiAgents::BookingSummary::INSTRUCTIONS)
          expect(schema.summary_request('show_booking_summary' => true, 'booking' => booking)).to eq(booking: nil, booking_rejection: nil)
        end

        it 'returns the booking the reply shows, as for a booking request' do
          expect(reply_schema.summary_request('show_booking_summary' => true, 'booking' => booking)).to eq(
            booking: { service: 'Cuci salon', customer_name: 'Budi', scheduled_at: Time.utc(2026, 11, 21, 2, 30), notes: nil,
                       details: { 'Plat nomor' => 'B 1234 CD' }, rescheduled_from_id: nil },
            booking_rejection: nil
          )
          expect(reply_schema.summary_request('show_booking_summary' => true, 'booking' => booking.merge('date' => 'besok')))
            .to eq(booking: nil, booking_rejection: :invalid_schedule)
          expect(reply_schema.summary_request('show_booking_summary' => true, 'booking' => booking.merge('service' => '')))
            .to eq(booking: nil, booking_rejection: :missing_service)
        end

        it 'returns no summary when the reply shows none or records the booking already' do
          [{ 'show_booking_summary' => false }, { 'show_booking_summary' => 'true' },
           { 'show_booking_summary' => true, 'create_booking' => true }].each do |flags|
            expect(reply_schema.summary_request(flags.merge('booking' => booking))).to eq(booking: nil, booking_rejection: nil), flags.inspect
          end
        end

        it 'leaves the summary out while the account lacks the bookings feature' do
          ai_agent.account.disable_features!('bookings')

          expect(reply_schema).not_to be_any
          expect(reply_schema.summary_request('show_booking_summary' => true, 'booking' => booking)).to eq(booking: nil, booking_rejection: nil)
        end
      end
    end

    it 'leaves bookings out while the account lacks the bookings feature' do
      expect(schema).not_to be_any
      expect(schema.instructions).to be_nil
      expect(schema.calendar).to be_nil
      expect(schema.known_text('booking' => booking)).to be_nil
      expect(schema.parse('create_booking' => true, 'booking' => booking, 'cancel_booking' => held.id.to_s))
        .to include(booking: nil, booking_rejection: nil, booking_cancellation: nil)
    end
  end
end
