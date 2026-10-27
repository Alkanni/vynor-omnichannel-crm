require 'rails_helper'

RSpec.describe Migration::RetrainAiAgentsJob do
  let(:legacy_agent) { create(:ai_agent) }
  let(:current_agent) { create(:ai_agent) }
  let(:keyword_agent) { create(:ai_agent) }

  before do
    { legacy_agent => [Array.new(1536, 0.1), nil], current_agent => [Array.new(2048, 0.1), 'nvidia/nvidia/nemotron-3-embed-1b'],
      keyword_agent => [nil, nil] }.each do |ai_agent, (embedding, embedding_model)|
      source = create(:ai_agent_knowledge_source, ai_agent: ai_agent)
      ai_agent.knowledge_chunks.create!(account: ai_agent.account, chunkable: source, chunkable_updated_at: source.updated_at,
                                        content: source.content, embedding: embedding, embedding_model: embedding_model)
    end
    allow(Redis::Alfred).to receive(:set).and_return(true)
  end

  it 'schedules training only for agents with chunks embedded before the embedding model was recorded' do
    expect { described_class.perform_now }
      .to have_enqueued_job(AiAgents::IndexKnowledgeJob).with(legacy_agent)
      .and have_enqueued_job(AiAgents::IndexKnowledgeJob).exactly(:once)
  end
end
