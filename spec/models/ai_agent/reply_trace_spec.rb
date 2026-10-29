require 'rails_helper'

RSpec.describe AiAgent::ReplyTrace do
  let(:account) { create(:account) }
  let(:ai_agent) { create(:ai_agent, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:message) { create(:message, account: account, inbox: inbox, conversation: conversation) }
  let!(:trace) do
    ai_agent.reply_traces.create!(account: account, conversation: conversation, message: message, model: ai_agent.model, status: :replied)
  end

  it 'is deleted with its AI agent' do
    ai_agent.destroy!

    expect(described_class.exists?(trace.id)).to be(false)
  end

  it 'is deleted with its conversation' do
    conversation.destroy!

    expect(described_class.exists?(trace.id)).to be(false)
  end
end
