require 'rails_helper'

RSpec.describe AiAgents::LlmClient do
  let(:usage) { { prompt_tokens: 1200, completion_tokens: 40, prompt_tokens_details: { cached_tokens: 1024 } } }
  let(:completion) do
    described_class.new.chat(model: 'gpt-4.1-mini', temperature: 0, instructions: 'Classify the turn.', messages: [{ role: :user, content: 'Halo' }],
                             schema: AiAgents::ScopeGuard::SCHEMA)
  end

  before do
    create(:installation_config, name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'test-key')
    stub_request(:post, 'https://api.openai.com/v1/chat/completions').to_return(
      status: 200, headers: { 'Content-Type' => 'application/json' },
      body: { id: 'chatcmpl-1', model: 'gpt-4.1-mini', usage: usage, choices: [{ message: { role: 'assistant', content: nil, tool_calls: [
        { id: 'call_1', type: 'function', function: { name: 'ai_agent_scope', arguments: { decision: 'GREETING' }.to_json } }
      ] } }] }.to_json
    )
  end

  it 'returns the arguments of the function call and the tokens, with the cached input apart from the input' do
    expect(completion).to have_attributes(content: { 'decision' => 'GREETING' }, input_tokens: 176, output_tokens: 40, cached_input_tokens: 1024)
  end

  context 'when the gateway does not report cached input' do
    let(:usage) { { prompt_tokens: 1200, completion_tokens: 40 } }

    it 'leaves the cached input tokens nil' do
      expect(completion).to have_attributes(input_tokens: 1200, output_tokens: 40, cached_input_tokens: nil)
    end
  end
end
