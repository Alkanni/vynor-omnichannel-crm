require 'rails_helper'

RSpec.describe Booking do
  let(:booking) { create(:booking) }

  it 'starts as requested' do
    expect(booking).to be_requested
  end

  it 'keeps the stored value of each status' do
    expect(described_class.statuses).to eq('requested' => 0, 'confirmed' => 1, 'cancelled' => 2, 'completed' => 3, 'no_show' => 4)
  end

  it 'needs a service, a customer name, and a time' do
    expect(described_class.new(service: ' ', customer_name: '', scheduled_at: nil)).not_to be_valid
  end

  it 'takes up to 255 characters of service and customer name, and up to 5,000 of notes' do
    booking.assign_attributes(service: 'a' * 255, customer_name: 'b' * 255, notes: 'c' * 5_000)
    expect(booking).to be_valid

    booking.assign_attributes(service: 'a' * 256, customer_name: 'b' * 256, notes: 'c' * 5_001)
    expect(booking).not_to be_valid
    expect(booking.errors.attribute_names).to contain_exactly(:service, :customer_name, :notes)
  end

  it 'moves on to the next statuses, but never back to requested nor away from cancelled' do
    expect(described_class::NEXT_STATUSES.keys).to match_array(described_class.statuses.keys)
    expect(described_class::NEXT_STATUSES.values.flatten).not_to include('requested')
    expect(described_class.new(status: :requested).next_statuses).to eq(%w[confirmed cancelled completed no_show])
    expect(described_class.new(status: :completed).next_statuses).to eq(%w[no_show])
    expect(described_class.new(status: :no_show).next_statuses).to eq(%w[completed])
    expect(described_class.new(status: :cancelled).next_statuses).to be_empty
  end

  it 'records a status change in its conversation with who made it, and nothing when the status stays' do
    user = create(:user, account: booking.account, name: 'Sari')

    booking.change_status!('confirmed', user)
    booking.change_status!('confirmed', user)

    expect(booking.reload).to be_confirmed
    expect(booking.conversation.messages.activity.pluck(:content)).to eq(["Sari marked booking ##{booking.id} as Confirmed"])
  end

  it 'names each status in the activity message' do
    user = create(:user, account: booking.account, name: 'Sari')

    %w[cancelled completed no_show requested].each { |status| booking.change_status!(status, user) }

    expect(booking.conversation.messages.activity.order(:id).pluck(:content)).to eq(
      %w[Cancelled Completed No-show Requested].map { |label| "Sari marked booking ##{booking.id} as #{label}" }
    )
  end

  it 'keeps the status when the activity message cannot be recorded' do
    allow(booking.conversation.messages).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)

    expect { booking.change_status!('confirmed', create(:user, account: booking.account)) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(booking.reload).to be_requested
  end

  describe 'the message to the customer' do
    let(:account) { booking.account }
    let(:conversation) { booking.conversation }
    let(:user) { create(:user, account: account, name: 'Sari') }
    let(:ai_agent) do
      create(:ai_agent, account: account,
                        booking_confirmed_message: 'Halo {{booking.customer_name}}, booking {{booking.service}} pada {{booking.date}} ' \
                                                   'jam {{booking.time}} sudah dikonfirmasi.',
                        booking_cancelled_message: 'Booking {{booking.id}} atas nama {{contact.name}} di {{account.name}} dibatalkan.')
    end
    let(:customer_messages) { conversation.messages.outgoing }

    before { booking.update!(ai_agent: ai_agent, service: 'Servis berkala', scheduled_at: Time.utc(2026, 11, 22, 7)) }

    it 'sends the confirmed message, with the date and time in the agent\'s time zone' do
      booking.change_status!('confirmed', user)

      expect(customer_messages.pluck(:content)).to eq(['Halo Budi, booking Servis berkala pada 22/11/2026 jam 14:00 sudah dikonfirmasi.'])
      expect(customer_messages.first).to have_attributes(private: false, sender: ai_agent, inbox_id: conversation.inbox_id)
      expect(conversation.messages.activity.pluck(:content)).to eq(["Sari marked booking ##{booking.id} as Confirmed"])
    end

    it 'sends the cancelled message, which can use the variables of any message' do
      conversation.contact.update!(name: 'budi santoso')
      account.update!(name: 'Bengkel Maju')

      booking.change_status!('cancelled', user)

      expect(customer_messages.pluck(:content)).to eq(["Booking #{booking.id} atas nama Budi Santoso di Bengkel Maju dibatalkan."])
    end

    it 'keeps the status when the message cannot be rendered, instead of sending the error to the customer' do
      ai_agent.update_column(:timezone, 'Mars/Olympus_Mons') # rubocop:disable Rails/SkipsModelValidations

      expect { booking.change_status!('confirmed', user) }.to raise_error(ArgumentError, /Invalid Timezone/)
      expect(booking.reload).to be_requested
      expect(customer_messages).to be_empty
    end

    it 'sends nothing for a status without a message, the same status again, or an empty message' do
      ai_agent.update!(booking_cancelled_message: '')

      %w[completed no_show requested confirmed confirmed cancelled].each { |status| booking.change_status!(status, user) }

      expect(customer_messages.count).to eq(1)
      expect(conversation.messages.activity.count).to eq(5)
    end

    it 'sends nothing for a booking without its AI agent' do
      ai_agent.destroy!

      booking.reload.change_status!('confirmed', user)

      expect(customer_messages).to be_empty
      expect(booking).to be_confirmed
    end

    it 'keeps a conversation the AI handles with the AI, and does not count the message as an AI reply' do
      create(:ai_agent_inbox, ai_agent: ai_agent, inbox: conversation.inbox)
      conversation.update!(status: :pending, ai_assignee: ai_agent)

      booking.change_status!('confirmed', user)

      expect(conversation.reload).to be_pending
      expect(conversation.ai_assignee).to eq(ai_agent)
      expect(AiAgents::ConversationSession.new(conversation: conversation, ai_agent: ai_agent).reply_count).to eq(0)
    end

    context 'with a WhatsApp conversation' do
      let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
      let(:booking) do
        inbox = create(:inbox, channel: channel, account: channel.account)
        create(:booking, account: channel.account, conversation: create(:conversation, inbox: inbox, account: channel.account))
      end

      it 'sends the message while the customer wrote in the last 24 hours' do
        create(:message, conversation: conversation, inbox: conversation.inbox, account: account, message_type: :incoming, created_at: 23.hours.ago)

        booking.change_status!('confirmed', user)

        expect(customer_messages.count).to eq(1)
      end

      it 'tells the staff instead once the reply window has closed, and still changes the status' do
        create(:message, conversation: conversation, inbox: conversation.inbox, account: account, message_type: :incoming, created_at: 25.hours.ago)

        booking.change_status!('confirmed', user)

        expect(customer_messages).to be_empty
        expect(booking.reload).to be_confirmed
        expect(conversation.messages.activity.order(:id).pluck(:content)).to eq(
          ["Sari marked booking ##{booking.id} as Confirmed",
           "The Confirmed message for booking ##{booking.id} was not sent to the customer because the channel's reply window has closed"]
        )
      end
    end
  end

  it 'goes with its conversation, and stays without the AI agent that requested it' do
    ai_agent = create(:ai_agent, account: booking.account)
    booking.update!(ai_agent: ai_agent)

    ai_agent.destroy!
    expect(booking.reload.ai_agent).to be_nil

    booking.conversation.destroy!
    expect(described_class.exists?(booking.id)).to be(false)
  end
end
