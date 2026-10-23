require 'rails_helper'

RSpec.describe AiAgentInbox do
  let(:account) { create(:account) }
  let(:ai_agent) { create(:ai_agent, account: account) }
  let(:inbox) { create(:inbox, account: account) }

  it 'connects an inbox to a single AI agent' do
    create(:ai_agent_inbox, ai_agent: ai_agent, inbox: inbox)
    other = build(:ai_agent_inbox, ai_agent: create(:ai_agent, account: account), inbox: inbox)

    expect(other).not_to be_valid
    expect(other.errors.full_messages).to include("#{inbox.name} is already connected to the AI agent #{ai_agent.name}")
  end

  it 'rejects inboxes of another account' do
    expect(build(:ai_agent_inbox, ai_agent: ai_agent, inbox: create(:inbox))).not_to be_valid
  end

  it 'rejects inboxes that use an active agent bot' do
    create(:agent_bot_inbox, inbox: inbox)

    expect(build(:ai_agent_inbox, ai_agent: ai_agent, inbox: inbox)).not_to be_valid
  end

  describe 'new conversations in a connected inbox' do
    before { create(:ai_agent_inbox, ai_agent: ai_agent, inbox: inbox) }

    it 'start as pending and are assigned to the AI agent' do
      conversation = create(:conversation, account: account, inbox: inbox)

      expect(inbox.active_bot?).to be(true)
      expect(conversation).to be_pending
      expect(conversation.ai_assignee).to eq(ai_agent)
      expect(conversation.assignee_type).to eq('AiAgent')
    end

    it 'keep a human assignee instead of the AI agent' do
      conversation = create(:conversation, :with_assignee, account: account, inbox: inbox)

      expect(conversation.ai_assignee).to be_nil
    end
  end

  it 'leaves conversations of inboxes without an AI agent untouched' do
    conversation = create(:conversation, account: account, inbox: inbox)

    expect(inbox.active_bot?).to be(false)
    expect(conversation).to be_open
  end
end
