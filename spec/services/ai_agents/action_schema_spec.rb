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
      before { ai_agent.account.enable_features!('bookings') }

      it 'asks for the core and the agent fields, with the condition, the bookings held, and the calendar' do
        properties = schema.json_schema('ai_agent_reply')[:schema][:properties]
        fields = %w[customer_name service date time notes] + ['Plat nomor']

        expect(properties[:create_booking]).to eq(type: 'boolean')
        expect(properties[:booking]).to eq(type: 'object', properties: fields.index_with { { type: 'string' } }, required: fields,
                                           additionalProperties: false)
        expect(schema.instructions).to include(described_class::BOOKING_INSTRUCTIONS, 'Saat customer ingin datang ke bengkel.',
                                               "Bookings already in this conversation:\nCuci salon, 2026-11-20 10:00, requested")
        travel_to(Time.utc(2026, 11, 19, 3, 0)) do
          expect(schema.calendar).to start_with('Calendar: Thursday 2026-11-19 (today), Friday 2026-11-20 (tomorrow), ' \
                                                'Saturday 2026-11-21 (the day after tomorrow), Sunday 2026-11-22,')
          expect(schema.calendar).to end_with('Thursday 2026-12-03')
        end
      end

      it 'gives the reply check the calendar and the time the reply fills in the booking' do
        travel_to(Time.utc(2026, 11, 19, 3, 0)) do
          expect(schema.known_text('booking' => booking)).to eq("#{schema.calendar}\n09:30")
          expect(schema.known_text('booking' => booking.merge('time' => 'pagi'))).to eq(schema.calendar)
        end
      end

      it 'returns the booking at its time in the agent time zone, with the agent fields as details' do
        expect(schema.parse('create_booking' => true, 'booking' => booking)).to include(
          booking: { service: 'Cuci salon', customer_name: 'Budi', scheduled_at: Time.utc(2026, 11, 21, 2, 30), notes: nil,
                     details: { 'Plat nomor' => 'B 1234 CD' } },
          booking_rejection: nil
        )
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

      it 'returns a booking without a name, which the conversation contact fills in' do
        expect(schema.parse('create_booking' => true, 'booking' => booking.merge('customer_name' => ' ')))
          .to include(booking: hash_including(service: 'Cuci salon', customer_name: ''), booking_rejection: nil)
      end

      it 'asks the model for the customer name when the conversation does not give it' do
        expect(described_class::BOOKING_INSTRUCTIONS.squish)
          .to include('asking for their name when the conversation does not give it, then read them a short summary')
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
    end

    it 'leaves bookings out while the account lacks the bookings feature' do
      expect(schema).not_to be_any
      expect(schema.instructions).to be_nil
      expect(schema.calendar).to be_nil
      expect(schema.known_text('booking' => booking)).to be_nil
      expect(schema.parse('create_booking' => true, 'booking' => booking)).to include(booking: nil, booking_rejection: nil)
    end
  end
end
