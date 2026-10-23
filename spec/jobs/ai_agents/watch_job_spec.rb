require 'rails_helper'

RSpec.describe AiAgents::WatchJob do
  let(:account) { create(:account) }
  let(:ai_agent) { create(:ai_agent, account: account, watcher_enabled: true, transfer_conditions: 'Transfer when the customer complains.') }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:watcher) { instance_double(AiAgents::Watcher, perform: { handoff: true, labels: ['complaint'], sheet_row: nil }) }

  before do
    create(:ai_agent_inbox, ai_agent: ai_agent, inbox: inbox)
    create(:label, account: account, title: 'complaint')
    create(:message, account: account, inbox: inbox, conversation: conversation, content: 'Pelayanannya buruk sekali')
    allow(AiAgents::Watcher).to receive(:new).and_return(watcher)
  end

  it 'applies the handoff and labels the reply missed' do
    described_class.perform_now(conversation)

    conversation.reload
    expect(conversation.label_list).to eq(['complaint'])
    expect(conversation).to be_open
    expect(conversation.messages.activity.where("additional_attributes ->> 'ai_agent_handoff' = 'watcher'")).to exist
    expect(AiAgents::Watcher).to have_received(:new)
      .with(ai_agent: ai_agent, messages: [hash_including(role: :user, content: 'Pelayanannya buruk sekali')], written_rows: [])
  end

  it 'skips conversations a human agent took over meanwhile' do
    conversation.open!

    described_class.perform_now(conversation)

    expect(AiAgents::Watcher).not_to have_received(:new)
  end

  it 'reports a failed check without handing the conversation off' do
    allow(watcher).to receive(:perform).and_raise(AiAgents::LlmError, 'The AI model request failed (ServerError)')
    tracker = instance_double(ChatwootExceptionTracker, capture_exception: true)
    allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)

    described_class.perform_now(conversation)

    expect(tracker).to have_received(:capture_exception)
    expect(conversation.reload).to be_pending
  end
end
