require 'rails_helper'

RSpec.describe BookingPolicy, type: :policy do
  subject { described_class }

  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:administrator_context) { { user: administrator, account: account, account_user: administrator.account_users.find_by(account: account) } }
  let(:agent_context) { { user: agent, account: account, account_user: agent.account_users.find_by(account: account) } }
  let(:inbox) { create(:inbox, account: account) }
  let!(:member_booking) { create(:booking, account: account, conversation: create(:conversation, account: account, inbox: inbox)) }
  let!(:other_inbox_booking) { create(:booking, account: account, conversation: create(:conversation, account: account)) }
  let!(:other_account_booking) { create(:booking) }

  before { create(:inbox_member, user: agent, inbox: inbox) }

  permissions :index?, :create?, :fields?, :update?, :history? do
    it 'allows administrators and agents while the account has the bookings feature' do
      account.enable_features!('bookings')

      expect(subject).to permit(administrator_context, Booking)
      expect(subject).to permit(agent_context, Booking)
    end

    it 'denies everyone while the account lacks the bookings feature' do
      expect(subject).not_to permit(administrator_context, Booking)
      expect(subject).not_to permit(agent_context, Booking)
    end
  end

  describe 'Scope' do
    it 'gives administrators every booking of the account' do
      expect(described_class::Scope.new(administrator_context, Booking.all).resolve).to contain_exactly(member_booking, other_inbox_booking)
    end

    it 'gives agents only the bookings of the conversations in their inboxes' do
      expect(described_class::Scope.new(agent_context, Booking.all).resolve).to contain_exactly(member_booking)
    end

    it 'leaves out the bookings of an inbox of another account the agent is a member of' do
      create(:inbox_member, user: agent, inbox: other_account_booking.conversation.inbox)

      expect(described_class::Scope.new(agent_context, Booking.all).resolve).to contain_exactly(member_booking)
    end
  end
end
