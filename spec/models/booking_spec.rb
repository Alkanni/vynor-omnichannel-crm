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

  it 'goes with its conversation, and stays without the AI agent that requested it' do
    ai_agent = create(:ai_agent, account: booking.account)
    booking.update!(ai_agent: ai_agent)

    ai_agent.destroy!
    expect(booking.reload.ai_agent).to be_nil

    booking.conversation.destroy!
    expect(described_class.exists?(booking.id)).to be(false)
  end
end
