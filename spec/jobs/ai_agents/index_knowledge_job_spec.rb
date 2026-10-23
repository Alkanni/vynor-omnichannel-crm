require 'rails_helper'

RSpec.describe AiAgents::IndexKnowledgeJob do
  let(:ai_agent) { create(:ai_agent) }
  let(:lock_key) { format(Redis::Alfred::AI_AGENT_TRAINING_LOCK, id: ai_agent.id) }
  let(:scheduled_key) { format(Redis::Alfred::AI_AGENT_TRAINING_SCHEDULED, id: ai_agent.id) }
  let(:indexer) { instance_double(AiAgents::KnowledgeIndexer, perform: true) }

  before do
    allow(AiAgents::KnowledgeIndexer).to receive(:new).with(ai_agent: ai_agent).and_return(indexer)
    Redis::Alfred.delete(lock_key)
    Redis::Alfred.set(scheduled_key, 1)
  end

  after do
    Redis::Alfred.delete(lock_key)
    Redis::Alfred.delete(scheduled_key)
  end

  it 'indexes the knowledge, clears the scheduled flag, and releases the lock' do
    described_class.perform_now(ai_agent)

    expect(indexer).to have_received(:perform)
    expect(Redis::Alfred.exists?(scheduled_key)).to be(false)
    expect(Redis::Alfred.exists?(lock_key)).to be(false)
  end

  it 'retries later while another indexing job holds the lock' do
    Redis::Alfred.set(lock_key, 1)

    expect { described_class.perform_now(ai_agent) }.to have_enqueued_job(described_class).with(ai_agent)
    expect(indexer).not_to have_received(:perform)
  end
end
