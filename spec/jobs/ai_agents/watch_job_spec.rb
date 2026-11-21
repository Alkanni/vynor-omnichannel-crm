require 'rails_helper'

RSpec.describe AiAgents::WatchJob do
  let(:account) { create(:account) }
  let(:ai_agent) { create(:ai_agent, account: account, watcher_enabled: true, transfer_conditions: 'Transfer when the customer complains.') }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:reply_trace) do
    create(:ai_agent_reply_trace, ai_agent: ai_agent, conversation: conversation, message: conversation.messages.incoming.sole, input_tokens: 1500,
                                  output_tokens: 60)
  end
  let(:result) do
    AiAgents::Watcher::Result.new(actions: { handoff: true, labels: ['complaint'], sheet_row: nil, booking: nil }, input_tokens: 300,
                                  output_tokens: 8, cached_input_tokens: 128)
  end
  let(:watcher) { instance_double(AiAgents::Watcher, perform: result) }

  before do
    create(:ai_agent_inbox, ai_agent: ai_agent, inbox: inbox)
    create(:label, account: account, title: 'complaint')
    create(:message, account: account, inbox: inbox, conversation: conversation, content: 'Pelayanannya buruk sekali')
    allow(AiAgents::Watcher).to receive(:new).and_return(watcher)
  end

  it 'applies the handoff and labels the reply missed, and adds its tokens to the trace of the reply' do
    described_class.perform_now(conversation, reply_trace)

    conversation.reload
    expect(conversation.label_list).to eq(['complaint'])
    expect(conversation).to be_open
    expect(conversation.messages.activity.where("additional_attributes ->> 'ai_agent_handoff' = 'watcher'")).to exist
    expect(AiAgents::Watcher).to have_received(:new)
      .with(ai_agent: ai_agent, messages: [hash_including(role: :user, content: 'Pelayanannya buruk sekali')], written_rows: [], bookings: [])
    expect(reply_trace.reload).to have_attributes(input_tokens: 1500, output_tokens: 60, watcher_input_tokens: 300, watcher_output_tokens: 8,
                                                  watcher_cached_input_tokens: 128)
  end

  context 'when the reply missed a booking' do
    let(:result) do
      booking = { service: 'Cuci salon', customer_name: '', scheduled_at: Time.utc(2026, 11, 20, 3, 0), notes: nil, details: {} }
      AiAgents::Watcher::Result.new(actions: { handoff: false, labels: [], sheet_row: nil, booking: booking }, input_tokens: 300, output_tokens: 8,
                                    cached_input_tokens: nil)
    end

    it 'requests it, under the contact name when the Watcher gave none' do
      ai_agent.update!(booking_enabled: true, booking_conditions: 'Saat customer ingin booking.',
                       booking_label_id: create(:label, account: account, title: 'booking').id)

      described_class.perform_now(conversation, reply_trace)

      expect(conversation.bookings.sole).to have_attributes(status: 'requested', scheduled_at: Time.utc(2026, 11, 20, 3, 0),
                                                            customer_name: conversation.contact.name)
    end
  end

  context 'when the Watcher finds the cancellation request the reply already noted' do
    let(:held) { create(:booking, account: account, conversation: conversation, status: :confirmed) }
    let(:result) do
      AiAgents::Watcher::Result.new(actions: { handoff: false, labels: [], sheet_row: nil, booking: nil, booking_cancellation: held.id },
                                    input_tokens: 300, output_tokens: 8, cached_input_tokens: nil)
    end

    it 'does not tell the staff again' do
      ai_agent.update!(booking_enabled: true, booking_conditions: 'Saat customer ingin booking.',
                       booking_label_id: create(:label, account: account, title: 'booking').id)
      AiAgents::ConversationSession.new(conversation: conversation, ai_agent: ai_agent)
                                   .apply!(handoff: false, labels: [], booking_cancellation: held.id, reason: :transfer_conditions)

      described_class.perform_now(conversation, reply_trace)

      expect(conversation.messages.activity.where("additional_attributes ->> 'ai_agent_booking_cancellation' IS NOT NULL").count).to eq(1)
      expect(held.reload).to be_confirmed
    end
  end

  context 'when the Watcher rejects the booking the reply already rejected' do
    let(:result) do
      AiAgents::Watcher::Result.new(actions: { handoff: false, labels: [], sheet_row: nil, booking: nil, booking_rejection: :missing_service },
                                    input_tokens: 300, output_tokens: 8, cached_input_tokens: nil)
    end

    it 'does not tell the staff again' do
      ai_agent.update!(booking_enabled: true, booking_conditions: 'Saat customer ingin booking.',
                       booking_label_id: create(:label, account: account, title: 'booking').id)
      AiAgents::ConversationSession.new(conversation: conversation, ai_agent: ai_agent)
                                   .apply!(handoff: false, labels: [], booking_rejection: :missing_service, reason: :transfer_conditions)

      described_class.perform_now(conversation, reply_trace)

      expect(conversation.messages.activity.where("additional_attributes ->> 'ai_agent_booking_rejected' IS NOT NULL").count).to eq(1)
    end
  end

  it 'logs its run, linked to the trace of the reply, with the request log on' do
    create(:installation_config, name: 'AI_AGENT_REQUEST_LOG_ENABLED', value: 'true')
    create(:installation_config, name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'test-key')
    allow(AiAgents::Watcher).to receive(:new).and_call_original
    stub_request(:post, 'https://api.openai.com/v1/chat/completions').to_return(
      status: 200, headers: { 'Content-Type' => 'application/json' },
      body: { id: 'chatcmpl-1', model: ai_agent.model, usage: { prompt_tokens: 300, completion_tokens: 8 },
              choices: [{ message: { role: 'assistant', content: nil, tool_calls: [
                { id: 'call_1', type: 'function', function: { name: 'ai_agent_watch', arguments: { handoff: true }.to_json } }
              ] } }] }.to_json
    )

    described_class.perform_now(conversation, reply_trace)

    log = AiAgent::RequestLog.sole
    expect(log).to have_attributes(source: 'watcher', status: 'ok', ai_agent_id: ai_agent.id, conversation_id: conversation.id,
                                   message_id: reply_trace.message_id, reply_trace_id: reply_trace.id,
                                   output: { 'handoff' => true, 'labels' => [], 'sheet_row' => nil, 'booking' => nil,
                                             'booking_rejection' => nil, 'booking_cancellation' => nil })
    expect(log.input['messages']).to eq([{ 'role' => 'user', 'content' => 'Pelayanannya buruk sekali', 'attachments' => [] }])
    expect(log.steps.sole).to include('step' => 'watcher', 'model' => ai_agent.model, 'output' => { 'handoff' => true },
                                      'tokens' => { 'input' => 300, 'output' => 8, 'cached_input' => nil })
    expect(log.steps.sole['input']['messages']).to eq([{ 'role' => 'user', 'content' => 'Customer: Pelayanannya buruk sekali' }])
  end

  it 'skips conversations a human agent took over meanwhile' do
    conversation.open!

    described_class.perform_now(conversation, reply_trace)

    expect(AiAgents::Watcher).not_to have_received(:new)
    expect(reply_trace.reload.watcher_input_tokens).to be_nil
  end

  it 'reports a failed check without handing the conversation off' do
    allow(watcher).to receive(:perform).and_raise(AiAgents::LlmError, 'The AI model request failed (ServerError)')
    tracker = instance_double(ChatwootExceptionTracker, capture_exception: true)
    allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)

    described_class.perform_now(conversation, reply_trace)

    expect(tracker).to have_received(:capture_exception)
    expect(conversation.reload).to be_pending
    expect(reply_trace.reload).to have_attributes(status: 'replied', watcher_input_tokens: nil, watcher_output_tokens: nil)
  end
end
