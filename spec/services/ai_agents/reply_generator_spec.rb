require 'rails_helper'

RSpec.describe AiAgents::ReplyGenerator do
  let(:ai_agent) do
    create(:ai_agent, behavior: 'Kamu adalah asisten Grand Sehat.', model: 'gpt-4.1-mini', temperature: 'precise',
                      timezone: 'Asia/Jakarta', context_limit: 1)
  end
  let(:source) { create(:ai_agent_knowledge_source, ai_agent: ai_agent) }
  let(:opening_hours) { Array.new(1536) { |index| index.zero? ? 1.0 : 0.0 } }
  let(:pricing) { Array.new(1536) { |index| index == 1 ? 1.0 : 0.0 } }
  let(:messages) do
    [
      { role: :user, content: 'Halo' },
      { role: :assistant, content: 'Halo, ada yang bisa dibantu?' },
      { role: :user, content: 'Jam buka?' },
      { role: :user, content: 'Hari Minggu juga?' }
    ]
  end
  let(:chat_requests) { [] }
  let(:embedding_requests) { [] }
  let(:reply_content) { { messages: ['Kami buka setiap hari pukul 07.30 - 18.00.', ' ', 'Ada lagi yang bisa dibantu?'] }.to_json }
  let(:reply_message) do
    { role: 'assistant', content: nil,
      tool_calls: [{ id: 'call_1', type: 'function', function: { name: 'ai_agent_reply', arguments: reply_content } }] }
  end

  before do
    create(:installation_config, name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'test-key')
    create(:installation_config, name: 'AI_AGENT_EMBEDDING_MODEL', value: 'text-embedding-3-small')
    ai_agent.knowledge_chunks.create!(account: ai_agent.account, chunkable: source, chunkable_updated_at: source.updated_at,
                                      content: 'Jam buka: setiap hari 07.30 - 18.00', embedding: opening_hours)
    ai_agent.knowledge_chunks.create!(account: ai_agent.account, chunkable: source, chunkable_updated_at: source.updated_at,
                                      content: 'Harga detailing: Rp750.000', embedding: pricing)
    stub_request(:post, 'https://api.openai.com/v1/embeddings').to_return do |request|
      embedding_requests << JSON.parse(request.body)
      { status: 200, headers: { 'Content-Type' => 'application/json' },
        body: { data: [{ embedding: opening_hours }], usage: { prompt_tokens: 4 } }.to_json }
    end
    stub_request(:post, 'https://api.openai.com/v1/chat/completions').to_return do |request|
      chat_requests << JSON.parse(request.body)
      { status: 200, headers: { 'Content-Type' => 'application/json' },
        body: { id: 'chatcmpl-1', model: 'gpt-4.1-mini', choices: [{ message: reply_message }],
                usage: { prompt_tokens: 10, completion_tokens: 5 } }.to_json }
    end
  end

  it 'returns the reply bubbles and sends the agent settings, knowledge, and history to the model' do
    travel_to(Time.utc(2026, 10, 22, 3, 0)) do
      expect(described_class.new(ai_agent: ai_agent, messages: messages).perform)
        .to eq(described_class::Reply.new(messages: ['Kami buka setiap hari pukul 07.30 - 18.00.', 'Ada lagi yang bisa dibantu?'],
                                          handoff: false, labels: []))
    end

    expect(embedding_requests.sole).to include('model' => 'text-embedding-3-small', 'input' => ["Jam buka?\nHari Minggu juga?"],
                                               'dimensions' => 1536)
    request = chat_requests.sole
    expect(request).to include('model' => 'gpt-4.1-mini', 'temperature' => 0.2,
                               'tool_choice' => { 'type' => 'function', 'function' => { 'name' => 'ai_agent_reply' } })
    system_prompt = request['messages'].first
    expect(system_prompt).to include('role' => 'developer')
    expect(system_prompt['content']).to include('Kamu adalah asisten Grand Sehat.', 'Thursday, 22 October 2026 10:00 (Asia/Jakarta)',
                                                'Jam buka: setiap hari 07.30 - 18.00')
    expect(system_prompt['content']).not_to include('Harga detailing')
    expect(request['messages'].drop(1).pluck('role', 'content')).to eq(messages.map { |message| [message[:role].to_s, message[:content]] })
  end

  it 'asks only for messages when the agent has no transfer conditions or allowed labels' do
    described_class.new(ai_agent: ai_agent, messages: messages).perform

    expect(chat_requests.sole['tools'].sole['function']['parameters']['properties'].keys).to eq(['messages'])
  end

  describe 'actions' do
    let(:reply_content) { { messages: ['Baik, kami sambungkan ke tim CS.'], handoff: true, labels: %w[complaint vip] }.to_json }

    before do
      ai_agent.update!(transfer_conditions: 'Transfer when the customer complains.', label_conditions: 'Apply complaint for complaints.',
                       allowed_label_ids: [create(:label, account: ai_agent.account, title: 'complaint').id])
      create(:label, account: ai_agent.account, title: 'vip')
    end

    it 'asks for the handoff and allowed labels, and drops labels outside the allowed list' do
      reply = described_class.new(ai_agent: ai_agent, messages: messages).perform

      expect(reply).to have_attributes(messages: ['Baik, kami sambungkan ke tim CS.'], handoff: true, labels: ['complaint'])
      request = chat_requests.sole
      schema = request['tools'].sole['function']['parameters']
      expect(schema['required']).to eq(%w[messages handoff labels])
      expect(schema['properties']['labels']).to eq('type' => 'array', 'items' => { 'type' => 'string', 'enum' => ['complaint'] })
      expect(request['messages'].first['content']).to include('Transfer when the customer complains.', 'Use only these labels: complaint',
                                                              'Apply complaint for complaints.')
    end

    context 'when a handoff comes without a note' do
      let(:reply_content) { { messages: [], handoff: true, labels: [] }.to_json }

      it 'returns the handoff instead of raising an empty reply error' do
        expect(described_class.new(ai_agent: ai_agent, messages: messages).perform).to have_attributes(messages: [], handoff: true)
      end
    end
  end

  it 'searches the knowledge by keywords when no embedding model is set' do
    InstallationConfig.find_by(name: 'AI_AGENT_EMBEDDING_MODEL').update!(value: '')

    described_class.new(ai_agent: ai_agent, messages: [{ role: :user, content: 'Berapa harga detailing?' }]).perform

    expect(embedding_requests).to be_empty
    expect(chat_requests.sole['messages'].first['content']).to include('Harga detailing: Rp750.000')
      .and(satisfy { |content| content.exclude?('Jam buka: setiap hari') })
  end

  context 'with an OpenAI-compatible gateway and a separate embedding endpoint' do
    let(:gateway_requests) { [] }

    before do
      create(:installation_config, name: 'CAPTAIN_OPEN_AI_ENDPOINT', value: 'http://9router.test:20128/')
      create(:installation_config, name: 'AI_AGENT_MODELS', value: 'cx/gpt-5.5')
      create(:installation_config, name: 'AI_AGENT_EMBEDDING_ENDPOINT', value: 'https://api.openai.com')
      create(:installation_config, name: 'AI_AGENT_EMBEDDING_API_KEY', value: 'embedding-key')
      ai_agent.update!(model: 'cx/gpt-5.5')
      stub_request(:post, 'http://9router.test:20128/v1/chat/completions').to_return do |request|
        gateway_requests << request
        { status: 200, headers: { 'Content-Type' => 'application/json' },
          body: { id: 'chatcmpl-1', model: 'cx/gpt-5.5', choices: [{ message: reply_message }] }.to_json }
      end
    end

    it 'sends the gateway model ID as is and embeds with the embedding key' do
      expect(described_class.new(ai_agent: ai_agent, messages: messages).perform.messages).to include('Ada lagi yang bisa dibantu?')

      request = gateway_requests.sole
      expect(JSON.parse(request.body)['model']).to eq('cx/gpt-5.5')
      expect(request.headers['Authorization']).to eq('Bearer test-key')
      expect(chat_requests).to be_empty
      expect(a_request(:post, 'https://api.openai.com/v1/embeddings').with(headers: { 'Authorization' => 'Bearer embedding-key' })).to have_been_made
    end
  end

  it 'skips the knowledge search when the agent has no knowledge' do
    ai_agent.knowledge_chunks.delete_all

    described_class.new(ai_agent: ai_agent, messages: messages).perform

    expect(embedding_requests).to be_empty
    expect(chat_requests.sole['messages'].first['content']).not_to include('<knowledge>')
  end

  context 'when the model answers in text instead of calling the reply function' do
    let(:reply_message) { { role: 'assistant', content: 'Kami buka setiap hari.' } }

    it 'raises an empty reply error' do
      expect { described_class.new(ai_agent: ai_agent, messages: messages).perform }
        .to raise_error(AiAgents::LlmError, 'The AI model returned an empty reply')
    end
  end

  context 'when the model returns no message' do
    let(:reply_content) { { messages: [] }.to_json }

    it 'raises an error instead of an empty reply' do
      expect { described_class.new(ai_agent: ai_agent, messages: messages).perform }
        .to raise_error(AiAgents::LlmError, 'The AI model returned an empty reply')
    end
  end

  it 'raises a readable error when the API key is not configured' do
    InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY').destroy!

    expect { described_class.new(ai_agent: ai_agent, messages: messages).perform }
      .to raise_error(AiAgents::LlmError, /API key is not configured/)
  end
end
