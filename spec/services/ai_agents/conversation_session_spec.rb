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
