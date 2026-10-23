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

  before do
    create(:installation_config, name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'test-key')
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
        body: { id: 'chatcmpl-1', model: 'gpt-4.1-mini', choices: [{ message: { role: 'assistant', content: reply_content } }],
                usage: { prompt_tokens: 10, completion_tokens: 5 } }.to_json }
    end
  end

  it 'returns the reply bubbles and sends the agent settings, knowledge, and history to the model' do
    travel_to(Time.utc(2026, 10, 22, 3, 0)) do
      expect(described_class.new(ai_agent: ai_agent, messages: messages).perform)
        .to eq(['Kami buka setiap hari pukul 07.30 - 18.00.', 'Ada lagi yang bisa dibantu?'])
    end

    expect(embedding_requests.sole).to include('model' => 'text-embedding-3-small', 'input' => ["Jam buka?\nHari Minggu juga?"])
    request = chat_requests.sole
    expect(request).to include('model' => 'gpt-4.1-mini', 'temperature' => 0.2, 'response_format' => hash_including('type' => 'json_schema'))
    system_prompt = request['messages'].first
    expect(system_prompt).to include('role' => 'developer')
    expect(system_prompt['content']).to include('Kamu adalah asisten Grand Sehat.', 'Thursday, 22 October 2026 10:00 (Asia/Jakarta)',
                                                'Jam buka: setiap hari 07.30 - 18.00')
    expect(system_prompt['content']).not_to include('Harga detailing')
    expect(request['messages'].drop(1).pluck('role', 'content')).to eq(messages.map { |message| [message[:role].to_s, message[:content]] })
  end

  it 'skips the knowledge search when the agent has no knowledge' do
    ai_agent.knowledge_chunks.delete_all

    described_class.new(ai_agent: ai_agent, messages: messages).perform

    expect(embedding_requests).to be_empty
    expect(chat_requests.sole['messages'].first['content']).not_to include('<knowledge>')
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
