require 'rails_helper'

RSpec.describe Booking do
  let(:booking) { create(:booking) }

  it 'starts as requested' do
    expect(booking).to be_requested
  end

  it 'needs a service, a customer name, and a time' do
    expect(described_class.new(service: ' ', customer_name: '', scheduled_at: nil)).not_to be_valid
  end

  it 'records a status change in its conversation with who made it, and nothing when the status stays' do
    user = create(:user, account: booking.account, name: 'Sari')

    booking.change_status!('confirmed', user)
    booking.change_status!('confirmed', user)

    expect(booking.reload).to be_confirmed
    expect(booking.conversation.messages.activity.pluck(:content)).to eq(["Sari marked booking ##{booking.id} as Confirmed"])
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
