require 'rails_helper'

RSpec.describe AiAgents::Watcher do
  let(:ai_agent) do
    create(:ai_agent, model: 'gpt-4.1-mini', transfer_conditions: 'Transfer when the customer complains.',
                      label_conditions: 'Apply complaint when the customer complains.')
  end
  let(:messages) do
    [{ role: :user, content: 'Pelayanannya buruk', attachments: [] }, { role: :assistant, content: 'Mohon maaf, Kak.', attachments: [] }]
  end
  let(:chat_requests) { [] }
  let(:reply_content) { { handoff: true, labels: %w[complaint vip] }.to_json }
  let(:tool_call) { { id: 'call_1', type: 'function', function: { name: 'ai_agent_watch', arguments: reply_content } } }

  before do
    ai_agent.update!(allowed_label_ids: [create(:label, account: ai_agent.account, title: 'complaint').id])
    create(:label, account: ai_agent.account, title: 'vip')
    create(:installation_config, name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'test-key')
    stub_request(:post, 'https://api.openai.com/v1/chat/completions').to_return do |request|
      chat_requests << JSON.parse(request.body)
      { status: 200, headers: { 'Content-Type' => 'application/json' },
        body: { id: 'chatcmpl-1', model: 'gpt-4.1-mini', usage: { prompt_tokens: 10, completion_tokens: 5 },
                choices: [{ message: { role: 'assistant', content: nil, tool_calls: [tool_call] } }] }.to_json }
    end
  end

  it 'asks the model which actions apply to the transcript, keeps only allowed labels, and returns the tokens of the call' do
    expect(described_class.new(ai_agent: ai_agent, messages: messages).perform)
      .to have_attributes(actions: { handoff: true, labels: ['complaint'], sheet_row: nil, booking: nil }, input_tokens: 10, output_tokens: 5,
                          cached_input_tokens: nil)

    request = chat_requests.sole
    expect(request).to include('model' => 'gpt-4.1-mini', 'temperature' => 0.2)
    expect(request['tools'].sole['function']['parameters']['properties'])
      .to eq('handoff' => { 'type' => 'boolean' }, 'labels' => { 'type' => 'array', 'items' => { 'type' => 'string', 'enum' => ['complaint'] } })
    expect(request['messages'].first['content']).to include('Transfer when the customer complains.', 'Apply complaint when the customer complains.')
    expect(request['messages'].last).to include('role' => 'user', 'content' => "Customer: Pelayanannya buruk\nAI agent: Mohon maaf, Kak.")
  end
end
