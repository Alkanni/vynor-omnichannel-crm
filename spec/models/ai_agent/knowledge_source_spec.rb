require 'rails_helper'

RSpec.describe AiAgent::KnowledgeSource do
  let(:ai_agent) { create(:ai_agent) }

  it 'takes the account of its AI agent' do
    source = create(:ai_agent_knowledge_source, ai_agent: ai_agent)

    expect(source.account_id).to eq(ai_agent.account_id)
  end

  it 'validates text sources' do
    source = build(:ai_agent_knowledge_source, ai_agent: ai_agent, title: 'a' * 256, content: 'a' * 100_001)

    expect(source).not_to be_valid
    expect(source.errors.attribute_names).to contain_exactly(:title, :content)
  end

  it 'allows a text source without content' do
    expect(build(:ai_agent_knowledge_source, ai_agent: ai_agent, content: nil)).to be_valid
  end

  it 'validates question and answer pairs' do
    source = build(:ai_agent_knowledge_source, :qa, ai_agent: ai_agent, title: '', content: '')
    expect(source).not_to be_valid
    expect(source.errors.attribute_names).to contain_exactly(:title, :content)

    source.assign_attributes(title: 'a' * 1_001, content: 'a' * 5_001)
    expect(source).not_to be_valid
    expect(source.errors.attribute_names).to contain_exactly(:title, :content)
  end

  it 'rejects unknown source types with a validation error' do
    source = build(:ai_agent_knowledge_source, ai_agent: ai_agent, source_type: 'video')

    expect(source).not_to be_valid
    expect(source.errors.attribute_names).to eq([:source_type])
  end
end
