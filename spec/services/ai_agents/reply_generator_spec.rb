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
    { 'Jam buka: setiap hari 07.30 - 18.00' => opening_hours, 'Harga detailing: Rp750.000' => pricing }.each do |content, embedding|
      ai_agent.knowledge_chunks.create!(account: ai_agent.account, chunkable: source, chunkable_updated_at: source.updated_at,
                                        content: content, embedding: embedding, embedding_model: 'text-embedding-3-small')
    end
    stub_request(:post, 'https://api.openai.com/v1/embeddings').to_return do |request|
      embedding_requests << JSON.parse(request.body)
      { status: 200, headers: { 'Content-Type' => 'application/json' },
        body: { data: JSON.parse(request.body)['input'].map { { embedding: opening_hours } }, usage: { prompt_tokens: 4 } }.to_json }
    end
    stub_request(:post, 'https://api.openai.com/v1/chat/completions').to_return do |request|
      chat_requests << JSON.parse(request.body)
      { status: 200, headers: { 'Content-Type' => 'application/json' },
        body: { id: 'chatcmpl-1', model: 'gpt-4.1-mini', choices: [{ message: reply_message }],
                usage: { prompt_tokens: 10, completion_tokens: 5 } }.to_json }
    end
  end

  it 'returns the reply bubbles and sends the agent settings, knowledge, and history to the model' do
    reply = travel_to(Time.utc(2026, 10, 22, 3, 0)) { described_class.new(ai_agent: ai_agent, messages: messages).perform }

    expect(reply).to have_attributes(messages: ['Kami buka setiap hari pukul 07.30 - 18.00.', 'Ada lagi yang bisa dibantu?'],
                                     handoff: false, labels: [], sheet_row: nil)
    expect(embedding_requests.sole).to eq('model' => 'text-embedding-3-small',
                                          'input' => ["query: Jam buka?\nHari Minggu juga?", "query: Halo\nJam buka?\nHari Minggu juga?"])
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

  describe 'business scope' do
    let(:system_prompt) do
      described_class.new(ai_agent: ai_agent, messages: messages).perform
      chat_requests.sole['messages'].first['content']
    end

    it 'adds nothing when the scope is off, whatever the policy fields hold' do
      ai_agent.update!(business_description: 'Toko roti', allowed_topics: 'Harga', disallowed_topics: 'Politik')

      expect(system_prompt).to start_with("Kamu adalah asisten Grand Sehat.\n\nCurrent date and time: ")
      expect(system_prompt).not_to include('business_scope', 'Toko roti', 'Politik')
    end

    it 'puts the rules and the policy of a strict agent after the behavior and before the knowledge' do
      ai_agent.update!(scope_mode: 'strict', business_description: 'Toko roti', allowed_topics: 'Harga', disallowed_topics: 'Politik')

      expect(system_prompt).to include("Business: Toko roti\nAllowed topics: Harga\nDisallowed topics: Politik\n</business_scope>")
      expect(system_prompt.index('Kamu adalah asisten Grand Sehat.')).to be < system_prompt.index(described_class::SCOPE_INSTRUCTIONS)
      expect(system_prompt.index('</business_scope>')).to be < system_prompt.index('<knowledge>')
    end

    it 'leaves out the disallowed topics when there are none' do
      ai_agent.update!(scope_mode: 'strict', business_description: 'Toko roti', allowed_topics: 'Harga')

      expect(system_prompt).to include("Allowed topics: Harga\n</business_scope>")
      expect(system_prompt).not_to include('Disallowed topics')
    end
  end

  it 'traces the knowledge it retrieved, the tokens the model reported, and the time it took' do
    trace = described_class.new(ai_agent: ai_agent, messages: messages).perform.trace

    expect(trace).to have_attributes(input_tokens: 10, output_tokens: 5, latency_ms: be >= 0)
    expect(trace.retrieval).to have_attributes(mode: 'hybrid', embedding_model: 'text-embedding-3-small')
    expect(trace.retrieval.hits.map { |hit| [hit.chunk.content, hit.rank] }).to eq([['Jam buka: setiap hari 07.30 - 18.00', 1]])
    expect(trace.attributes).to include(retrieval_mode: 'hybrid', embedding_model: 'text-embedding-3-small', input_tokens: 10, output_tokens: 5,
                                        retrieved: [{ chunk_id: ai_agent.knowledge_chunks.find_by!(content: 'Jam buka: setiap hari 07.30 - 18.00').id,
                                                      chunkable_type: 'AiAgent::KnowledgeSource', chunkable_id: source.id, rank: 1,
                                                      score: be_within(1e-9).of(7.5 / 21) }])
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
      reply = described_class.new(ai_agent: ai_agent, messages: messages).perform

      expect(reply.messages).to include('Ada lagi yang bisa dibantu?')
      expect(reply.trace).to have_attributes(input_tokens: nil, output_tokens: nil)

      request = gateway_requests.sole
      expect(JSON.parse(request.body)['model']).to eq('cx/gpt-5.5')
      expect(request.headers['Authorization']).to eq('Bearer test-key')
      expect(chat_requests).to be_empty
      expect(a_request(:post, 'https://api.openai.com/v1/embeddings').with(headers: { 'Authorization' => 'Bearer embedding-key' })).to have_been_made
    end
  end

  it 'leaves out chunks embedded with another model until the agent is trained again' do
    InstallationConfig.find_by(name: 'AI_AGENT_EMBEDDING_MODEL').update!(value: 'nvidia/nvidia/nemotron-3-embed-1b')

    described_class.new(ai_agent: ai_agent, messages: messages).perform

    expect(embedding_requests).to be_empty
    expect(chat_requests.sole['messages'].first['content']).not_to include('<knowledge>')
  end

  it 'searches chunks of any vector size with the model they were embedded with' do
    nemotron = Array.new(2048) { |index| index.zero? ? 1.0 : 0.0 }
    InstallationConfig.find_by(name: 'AI_AGENT_EMBEDDING_MODEL').update!(value: 'nvidia/nvidia/nemotron-3-embed-1b')
    ai_agent.knowledge_chunks.create!(account: ai_agent.account, chunkable: source, chunkable_updated_at: source.updated_at,
                                      content: 'Promo: gratis cuci mobil', embedding: nemotron, embedding_model: 'nvidia/nvidia/nemotron-3-embed-1b')
    stub_request(:post, 'https://api.openai.com/v1/embeddings')
      .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: { data: [{ embedding: nemotron }] }.to_json)

    described_class.new(ai_agent: ai_agent, messages: messages).perform

    expect(chat_requests.sole['messages'].first['content']).to include('Promo: gratis cuci mobil')
      .and(satisfy { |content| content.exclude?('Jam buka: setiap hari') })
  end

  it 'sends no knowledge but keeps the rule against unknown facts when no chunk is relevant' do
    create(:installation_config, name: 'AI_AGENT_EMBEDDING_MAX_DISTANCE', value: '0.5')
    stub_request(:post, 'https://api.openai.com/v1/embeddings').to_return(
      status: 200, headers: { 'Content-Type' => 'application/json' },
      body: { data: [{ embedding: Array.new(1536) { |index| index == 2 ? 1.0 : 0.0 } }] }.to_json
    )

    reply = described_class.new(ai_agent: ai_agent, messages: [{ role: :user, content: 'Ada promo?' }]).perform

    system_prompt = chat_requests.sole['messages'].first['content']
    expect(system_prompt).to include(described_class::NO_RELEVANT_KNOWLEDGE_INSTRUCTIONS.strip)
    expect(system_prompt).not_to include('<knowledge>')
    expect(reply.trace.retrieval.hits).to be_empty
  end

  it 'skips the knowledge search when the agent has no knowledge' do
    ai_agent.knowledge_chunks.delete_all

    described_class.new(ai_agent: ai_agent, messages: messages).perform

    expect(embedding_requests).to be_empty
    expect(chat_requests.sole['messages'].first['content']).not_to include('<knowledge>', 'None of your knowledge')
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
