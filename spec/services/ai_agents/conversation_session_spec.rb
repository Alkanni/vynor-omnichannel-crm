require 'rails_helper'

RSpec.describe AiAgents::ConversationSession do
  let(:account) { create(:account) }
  let(:ai_agent) { create(:ai_agent, account: account, history_limit: 3) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:session) { described_class.new(conversation: conversation, ai_agent: ai_agent) }

  let(:message_attributes) { { account: account, inbox: inbox, conversation: conversation } }

  before { create(:ai_agent_inbox, ai_agent: ai_agent, inbox: inbox) }

  describe '#history' do
    it 'returns the latest messages up to the history limit, oldest first' do
      create(:message, **message_attributes, content: 'Halo')
      create(:message, **message_attributes, message_type: :outgoing, content: 'Halo juga')
      create(:message, **message_attributes, message_type: :outgoing, private: true, content: 'Catatan internal')
      create(:message, **message_attributes, content: 'Jam buka?')
      create(:message, **message_attributes, content: 'Hari ini?')

      expect(session.history.map { |entry| entry.slice(:role, :content) }).to eq(
        [{ role: :assistant, content: 'Halo juga' }, { role: :user, content: 'Jam buka?' }, { role: :user, content: 'Hari ini?' }]
      )
    end

    it 'starts with the welcome message even when it was posted after the first customer message' do
      create(:message, **message_attributes, content: 'Toko buka jam berapa?')
      create(:message, **message_attributes, message_type: :outgoing, sender: ai_agent, content: 'Halo! Ada yang bisa kami bantu?',
                                             additional_attributes: { 'ai_agent_welcome' => true })

      expect(session.history.map { |entry| entry.slice(:role, :content) }).to eq(
        [{ role: :assistant, content: 'Halo! Ada yang bisa kami bantu?' }, { role: :user, content: 'Toko buka jam berapa?' }]
      )
    end

    it 'keeps only the current session when session-only memory is on' do
      create(:message, **message_attributes, content: 'Pertanyaan lama')
      create(:reporting_event, name: 'conversation_resolved', account: account, inbox: inbox, conversation: conversation,
                               event_end_time: Time.current)
      create(:message, **message_attributes, content: 'Pertanyaan baru')

      expect(session.history.pluck(:content)).to eq(['Pertanyaan lama', 'Pertanyaan baru'])
      ai_agent.update!(session_only_memory: true)
      expect(session.history.pluck(:content)).to eq(['Pertanyaan baru'])
    end

    it 'attaches images only from the messages within the read file limit' do
      ai_agent.update!(read_file_limit: 1)
      create(:message, :with_attachment, **message_attributes, content: 'Foto lama')
      create(:message, :with_attachment, **message_attributes, content: 'Foto baru')

      attachments = session.history.pluck(:attachments)

      expect(attachments.first).to be_empty
      expect(attachments.last).to contain_exactly(an_instance_of(ActiveStorage::Blob))
    end
  end

  describe '#apply! with a booking' do
    let(:label) { create(:label, account: account, title: 'booking') }
    let(:booking) do
      { service: 'Cuci salon', customer_name: 'Budi', scheduled_at: Time.utc(2026, 11, 20, 3, 0), notes: nil,
        details: { 'Plat nomor' => 'B 1234 CD' } }
    end
    let(:arguments) { { handoff: false, labels: [], booking: booking, reason: :transfer_conditions } }

    before { ai_agent.update!(booking_enabled: true, booking_conditions: 'Saat customer ingin booking.', booking_label_id: label.id) }

    it 'records the booking as requested, labels the conversation, and tells the staff' do
      session.apply!(**arguments)

      requested = conversation.bookings.sole
      expect(requested).to have_attributes(account: account, contact: conversation.contact, ai_agent: ai_agent, status: 'requested',
                                           service: 'Cuci salon', customer_name: 'Budi', scheduled_at: Time.utc(2026, 11, 20, 3, 0),
                                           details: { 'Plat nomor' => 'B 1234 CD' })
      expect(conversation.reload.label_list).to eq(['booking'])
      expect(conversation.messages.activity.pluck(:content))
        .to include("#{ai_agent.name} recorded booking request ##{requested.id}: Cuci salon, 2026-11-20 10:00 WIB")
      expect(session.bookings).to eq([requested])
    end

    it 'does not request a booking the customer still has, and requests one that was cancelled again' do
      held = create(:booking, account: account, conversation: conversation, service: 'cuci SALON', scheduled_at: booking[:scheduled_at])
      expect { session.apply!(**arguments) }.not_to change(Booking, :count)

      held.cancelled!
      expect { session.apply!(**arguments) }.to change(Booking, :count).by(1)
    end

    it 'does not request a confirmed booking again, and requests the same service at another time' do
      create(:booking, account: account, conversation: conversation, status: :confirmed, scheduled_at: booking[:scheduled_at])
      expect { session.apply!(**arguments) }.not_to change(Booking, :count)

      later = booking.merge(scheduled_at: booking[:scheduled_at] + 1.hour)
      expect { session.apply!(handoff: false, labels: [], booking: later, reason: :transfer_conditions) }.to change(Booking, :count).by(1)
    end

    it 'records the booking with its notes and hands the conversation off when both are asked for' do
      session.apply!(handoff: true, labels: [], booking: booking.merge(notes: 'Bawa STNK'), reason: :transfer_conditions)

      expect(conversation.bookings.sole.notes).to eq('Bawa STNK')
      expect(conversation.reload).to be_open
      expect(conversation.ai_assignee).to be_nil
    end

    it 'records the booking without a label once the label was deleted' do
      label.destroy!

      session.apply!(**arguments)

      expect(conversation.bookings.count).to eq(1)
      expect(conversation.reload.label_list).to be_empty
    end

    it 'records a booking the model gave no name for under the contact name' do
      conversation.contact.update!(name: ' Budi Santoso ')

      session.apply!(**arguments, booking: booking.merge(customer_name: ''))

      expect(conversation.bookings.sole.customer_name).to eq('Budi Santoso')
    end

    context 'when the booking cannot be recorded' do
      let(:rejections) { conversation.messages.activity.where("additional_attributes ->> 'ai_agent_booking_rejected' IS NOT NULL") }
      let(:rejection) { { handoff: false, labels: [], reason: :transfer_conditions } }

      it 'tells the staff why with the booking label, once per customer message, without a handoff' do
        create(:message, **message_attributes, content: 'Ya, sudah benar')

        2.times { session.apply!(**rejection, booking_rejection: :invalid_schedule) }

        expect(rejections.pluck(:content)).to eq(["#{ai_agent.name} could not record the booking the customer asked for because the date or " \
                                                  'time is missing or not valid. Follow it up with the customer.'])
        expect(conversation.reload.label_list).to eq(['booking'])
        expect(conversation.bookings).to be_empty
        expect(conversation.messages.activity.where("additional_attributes ->> 'ai_agent_handoff' IS NOT NULL")).not_to exist

        create(:message, **message_attributes, content: 'Cuci salon ya')
        session.apply!(**rejection, booking_rejection: :missing_service)

        expect(rejections.count).to eq(2)
      end

      it 'tells the staff when the booking time has passed' do
        session.apply!(**rejection, booking_rejection: :past_schedule)

        expect(rejections.sole.content).to include('because the date and time have already passed')
      end

      it 'rejects a booking without a name when the contact has none either' do
        conversation.contact.update!(name: '')

        session.apply!(**arguments, booking: booking.merge(customer_name: ''))

        expect(conversation.bookings).to be_empty
        expect(rejections.sole.content).to include('because the customer name is missing')
      end
    end

    context 'when the customer reschedules a booking they have' do
      let!(:held) do
        create(:booking, account: account, conversation: conversation, status: :confirmed, scheduled_at: Time.utc(2026, 11, 19, 3, 0))
      end

      before do
        ai_agent.update!(booking_confirmed_message: 'Booking dikonfirmasi.', booking_cancelled_message: 'Booking dibatalkan.')
        held.update!(ai_agent: ai_agent)
      end

      it 'records the new booking in its place and marks it rescheduled, without a message to the customer' do
        session.apply!(**arguments, booking: booking.merge(rescheduled_from_id: held.id))

        replacement = conversation.bookings.requested.sole
        expect(replacement.rescheduled_from).to eq(held)
        expect(held.reload).to be_rescheduled
        expect(session.bookings).to eq([replacement])
        expect(conversation.messages.outgoing).to be_empty
        expect(conversation.messages.activity.pluck(:content))
          .to include("#{ai_agent.name} recorded booking request ##{replacement.id}: Cuci salon, 2026-11-20 10:00 WIB, " \
                      "which replaces booking ##{held.id}")
        expect(conversation.reload.label_list).to eq(['booking'])
      end

      it 'records the new booking without a link when the staff changed the earlier one meanwhile' do
        held.cancelled!

        session.apply!(**arguments, booking: booking.merge(rescheduled_from_id: held.id))

        expect(conversation.bookings.requested.sole.rescheduled_from).to be_nil
        expect(held.reload).to be_cancelled
      end
    end

    context 'when the customer asks to cancel a booking they have' do
      let!(:held) { create(:booking, account: account, conversation: conversation, status: :confirmed) }
      let(:cancellations) { conversation.messages.activity.where("additional_attributes ->> 'ai_agent_booking_cancellation' IS NOT NULL") }
      let(:cancellation) { { handoff: false, labels: [], reason: :transfer_conditions, booking_cancellation: held.id } }

      it 'tells the staff once per customer message, with the booking label, and keeps the booking' do
        create(:message, **message_attributes, content: 'Batalkan booking saya ya')

        2.times { session.apply!(**cancellation) }

        expect(cancellations.sole.content).to start_with("The customer asked #{ai_agent.name} to cancel booking ##{held.id} (Cuci salon,")
        expect(held.reload).to be_confirmed
        expect(conversation.reload.label_list).to eq(['booking'])
      end

      it 'notes nothing for a booking the customer no longer has' do
        held.cancelled!

        session.apply!(**cancellation)

        expect(cancellations).to be_empty
      end
    end
  end

  describe '#bookings' do
    it 'lists the requested and confirmed bookings of the conversation, soonest first' do
      later = create(:booking, account: account, conversation: conversation, scheduled_at: 2.days.from_now)
      sooner = create(:booking, account: account, conversation: conversation, status: :confirmed, scheduled_at: 1.day.from_now)
      %i[cancelled completed no_show].each { |status| create(:booking, account: account, conversation: conversation, status: status) }
      create(:booking, account: account)

      expect(session.bookings).to eq([sooner, later])
    end
  end

  describe '#reply_count' do
    it 'counts AI replies in the current session, not their bubbles' do
      first = create(:message, **message_attributes, content: 'Halo')
      2.times { |index| session.reply!("Bubble #{index}", to: first) }
      session.reply!('Balasan kedua', to: create(:message, **message_attributes, content: 'Lagi'))

      expect(session.reply_count).to eq(2)

      create(:reporting_event, name: 'conversation_resolved', account: account, inbox: inbox, conversation: conversation,
                               event_end_time: Time.current)
      expect(session.reply_count).to eq(0)
    end

    it 'counts only the replies since a human handed the conversation back to the AI' do
      session.reply!('Balasan pertama', to: create(:message, **message_attributes, content: 'Halo'))
      session.handoff!(:message_limit)

      travel_to(1.minute.from_now) { conversation.pending! }
      expect(session.reply_count).to eq(0)

      travel_to(2.minutes.from_now) { session.reply!('Balasan baru', to: create(:message, **message_attributes, content: 'Saya kembali')) }
      expect(session.reply_count).to eq(1)
    end
  end

  describe '#promotion_ids' do
    it 'returns the promotions the AI replies of the current session mentioned, once each' do
      question = create(:message, **message_attributes, content: 'Ada promo?')
      2.times { |index| session.reply!("Bubble #{index}", to: question, promotion_id: 4) }
      session.reply!('Ada promo lain', to: create(:message, **message_attributes, content: 'Lainnya?'), promotion_id: 9)
      without_promotion = session.reply!('Jam buka 08.00', to: create(:message, **message_attributes, content: 'Jam buka?'))
      create(:message, **message_attributes, message_type: :outgoing, content: 'Dari staf', additional_attributes: { 'ai_agent_promotion' => 5 })

      expect(session.promotion_ids).to contain_exactly(4, 9)
      expect(without_promotion.additional_attributes.keys).to eq(['ai_agent_reply_to'])
    end

    it 'starts again with none after the conversation is resolved' do
      session.reply!('Ada promo', to: create(:message, **message_attributes, content: 'Ada promo?'), promotion_id: 4)

      create(:reporting_event, name: 'conversation_resolved', account: account, inbox: inbox, conversation: conversation,
                               event_end_time: Time.current)
      expect(session.promotion_ids).to be_empty
    end
  end

  describe '.event_data' do
    it 'names the agent and whether it answers the conversation now' do
      expect(described_class.event_data(conversation)).to eq(id: ai_agent.id, name: ai_agent.name, active: true)

      session.handoff!(:transfer_conditions)
      expect(described_class.event_data(conversation)).to eq(id: ai_agent.id, name: ai_agent.name, active: false)
    end

    it 'is nil for a conversation in an inbox without an AI agent' do
      expect(described_class.event_data(create(:conversation, account: account))).to be_nil
    end
  end

  describe '#handoff!' do
    it 'opens the conversation, clears the AI assignee, and records why' do
      session.handoff!(:transfer_conditions)

      conversation.reload
      expect(conversation).to be_open
      expect(conversation.ai_assignee).to be_nil
      expect(conversation.messages.activity.sole.additional_attributes).to eq('ai_agent_handoff' => 'transfer_conditions')
    end

    it 'does nothing once the conversation left the AI' do
      conversation.open!

      session.handoff!(:transfer_conditions)

      expect(conversation.messages.activity.where("additional_attributes ->> 'ai_agent_handoff' IS NOT NULL")).to be_empty
    end
  end

  describe '#ai_active?' do
    it 'is on for pending conversations and, after a handoff, only while the AI may keep replying' do
      expect(session.ai_active?).to be(true)

      session.handoff!(:transfer_conditions)
      expect(session.ai_active?).to be(false)

      ai_agent.update!(stop_ai_after_handoff: false)
      expect(session.ai_active?).to be(true)

      create(:message, **message_attributes, message_type: :outgoing, private: true, sender: create(:user, account: account))
      expect(session.ai_active?).to be(true)

      create(:message, **message_attributes, message_type: :outgoing, sender: create(:user, account: account))
      expect(session.ai_active?).to be(false)
    end

    it 'is off for conversations a human opened without an AI handoff' do
      ai_agent.update!(stop_ai_after_handoff: false)
      conversation.open!

      expect(session.ai_active?).to be(false)
    end
  end

  describe '#send_pending_message' do
    let(:pending_messages) { conversation.messages.outgoing.where(sender: ai_agent) }

    before do
      ai_agent.update!(pending_assigned_message: 'Agen kami segera membalas.', pending_unassigned_message: 'Mohon tunggu, kami carikan agen.')
      session.handoff!(:transfer_conditions)
    end

    it 'tells the customer once per handoff whether an agent is assigned' do
      2.times { session.send_pending_message }
      conversation.update!(assignee: create(:user, account: account))
      2.times { session.send_pending_message }

      expect(pending_messages.pluck(:content)).to eq(['Mohon tunggu, kami carikan agen.', 'Agen kami segera membalas.'])
      expect(pending_messages.map { |message| message.additional_attributes['ai_agent_pending'] }).to eq(%w[unassigned assigned])
      expect(conversation.reload.waiting_since).to be_present
    end

    it 'sends nothing on a silent handoff, after a human reply, or when the message is empty' do
      ai_agent.update!(silent_handoff: true)
      session.send_pending_message

      ai_agent.update!(silent_handoff: false, pending_unassigned_message: '')
      session.send_pending_message

      ai_agent.update!(pending_unassigned_message: 'Mohon tunggu.')
      create(:message, **message_attributes, message_type: :outgoing, sender: create(:user, account: account))
      session.send_pending_message

      expect(pending_messages).to be_empty
    end

    it 'starts over with the next handoff' do
      session.send_pending_message
      conversation.update!(status: :pending)
      session.handoff!(:message_limit)
      session.send_pending_message

      expect(pending_messages.count).to eq(2)
    end
  end
end
