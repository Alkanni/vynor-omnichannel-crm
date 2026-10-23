require 'rails_helper'

RSpec.describe AiAgents::ReplyJob do
  let(:account) { create(:account) }
  let(:ai_agent) { create(:ai_agent, account: account, message_limit: 2) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:message_attributes) { { account: account, inbox: inbox, conversation: conversation } }
  let(:generator) { instance_double(AiAgents::ReplyGenerator, perform: ['Halo!', 'Ada yang bisa dibantu?']) }
  let(:ai_replies) { conversation.messages.where(sender: ai_agent) }

  before do
    create(:ai_agent_inbox, ai_agent: ai_agent, inbox: inbox)
    allow(AiAgents::ReplyGenerator).to receive(:new).and_return(generator)
  end

  it 'sends each reply item as a separate message from the AI agent' do
    message = create(:message, **message_attributes, content: 'Halo')

    described_class.perform_now(message)

    expect(ai_replies.outgoing.pluck(:content)).to eq(['Halo!', 'Ada yang bisa dibantu?'])
    expect(ai_replies.map { |reply| reply.additional_attributes['ai_agent_reply_to'] }.uniq).to eq([message.id])
    expect(conversation.reload).to be_pending
  end

  it 'answers a burst of messages once, from the job of the latest message' do
    messages = ['Halo', 'Mau tanya', 'Harga detailing?'].map { |content| create(:message, **message_attributes, content: content) }

    messages.each { |message| described_class.perform_now(message) }

    expect(AiAgents::ReplyGenerator).to have_received(:new).once
    expect(AiAgents::ReplyGenerator).to have_received(:new)
      .with(ai_agent: ai_agent, messages: array_including(hash_including(content: 'Halo'), hash_including(content: 'Harga detailing?')))
    expect(ai_replies.count).to eq(2)
  end

  it 'drops the reply when the customer wrote again while it was generated' do
    message = create(:message, **message_attributes, content: 'Halo')
    allow(generator).to receive(:perform) do
      create(:message, **message_attributes, content: 'Masih di sana?')
      ['Halo!']
    end

    described_class.perform_now(message)

    expect(ai_replies).to be_empty
  end

  it 'does not answer conversations that are no longer pending' do
    message = create(:message, **message_attributes, content: 'Halo')
    conversation.open!

    described_class.perform_now(message)

    expect(AiAgents::ReplyGenerator).not_to have_received(:new)
    expect(ai_replies).to be_empty
  end

  it 'hands the conversation off once the AI message limit is reached in the session' do
    session = AiAgents::ConversationSession.new(conversation: conversation, ai_agent: ai_agent)
    2.times { session.reply!('Balasan', to: create(:message, **message_attributes)) }
    message = create(:message, **message_attributes, content: 'Pertanyaan ketiga')

    described_class.perform_now(message)

    expect(AiAgents::ReplyGenerator).not_to have_received(:new)
    expect(conversation.reload).to be_open
    expect(ai_replies.count).to eq(2)
  end

  it 'hands the conversation off without replying when the model fails' do
    message = create(:message, **message_attributes, content: 'Halo')
    allow(generator).to receive(:perform).and_raise(AiAgents::LlmError, 'The AI model request failed (timeout)')
    tracker = instance_double(ChatwootExceptionTracker, capture_exception: true)
    allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)

    described_class.perform_now(message)

    expect(ai_replies).to be_empty
    expect(conversation.reload).to be_open
    expect(tracker).to have_received(:capture_exception)
  end
end
