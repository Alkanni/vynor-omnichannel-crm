require 'rails_helper'

RSpec.describe 'AI Agent knowledge sources API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:ai_agent) { create(:ai_agent, account: account) }
  let(:base_url) { "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/knowledge_sources" }

  describe 'GET index' do
    let!(:text_source) { create(:ai_agent_knowledge_source, ai_agent: ai_agent) }
    let!(:older_qa) { create(:ai_agent_knowledge_source, :qa, ai_agent: ai_agent) }
    let!(:newer_qa) { create(:ai_agent_knowledge_source, :qa, ai_agent: ai_agent) }

    it 'returns the sources of the requested type, newest Q&A first' do
      get base_url, params: { source_type: 'qa' }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload'].pluck('id')).to eq([newer_qa.id, older_qa.id])
    end

    it 'returns text sources in creation order' do
      second_text = create(:ai_agent_knowledge_source, ai_agent: ai_agent)

      get base_url, params: { source_type: 'text' }, headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['payload'].pluck('id')).to eq([text_source.id, second_text.id])
    end

    it 'rejects a missing or unknown source type' do
      get base_url, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)

      get base_url, params: { source_type: 'video' }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'returns unauthorized for agents' do
      get base_url, params: { source_type: 'text' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns not found for an AI agent of another account' do
      other_ai_agent = create(:ai_agent)

      get "/api/v1/accounts/#{account.id}/ai_agents/#{other_ai_agent.id}/knowledge_sources",
          params: { source_type: 'text' }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST create' do
    it 'creates a text source' do
      post base_url, params: { source_type: 'text', title: 'Promo', content: 'Promo spesial' },
                     headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(ai_agent.knowledge_sources.text.pluck(:title, :content, :account_id)).to eq([['Promo', 'Promo spesial', account.id]])
    end

    it 'rejects a question without an answer' do
      post base_url, params: { source_type: 'qa', title: 'Jam buka?', content: '' }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['attributes']).to eq(['content'])
    end

    it 'rejects an unknown source type' do
      post base_url, params: { source_type: 'video', title: 'Video' }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'returns unauthorized for agents' do
      post base_url, params: { source_type: 'text', title: 'Promo' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(ai_agent.knowledge_sources.count).to eq(0)
    end
  end

  describe 'PATCH update' do
    let!(:source) { create(:ai_agent_knowledge_source, ai_agent: ai_agent) }

    it 'updates title and content but not the source type' do
      patch "#{base_url}/#{source.id}", params: { title: 'Derek', content: 'Layanan derek 24 jam', source_type: 'qa' },
                                        headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(source.reload).to have_attributes(title: 'Derek', content: 'Layanan derek 24 jam', source_type: 'text')
    end

    it 'returns not found for a source of another AI agent' do
      other_source = create(:ai_agent_knowledge_source, ai_agent: create(:ai_agent, account: account))

      patch "#{base_url}/#{other_source.id}", params: { title: 'Changed' }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
      expect(other_source.reload.title).not_to eq('Changed')
    end
  end

  describe 'DELETE destroy' do
    it 'deletes the source' do
      source = create(:ai_agent_knowledge_source, ai_agent: ai_agent)

      delete "#{base_url}/#{source.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(AiAgent::KnowledgeSource.exists?(source.id)).to be(false)
    end
  end

  describe 'GET stats' do
    it 'returns the knowledge statistics' do
      create(:ai_agent_knowledge_source, ai_agent: ai_agent, content: 'abcde')
      create(:ai_agent_product, ai_agent: ai_agent, name: 'ab', description: nil)

      get "#{base_url}/stats", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to eq(
        'text_characters' => 5, 'qa_count' => 0, 'qa_characters' => 0, 'products' => 1, 'total_characters' => 7
      )
    end
  end

  it 'deletes knowledge sources and products with their AI agent' do
    source = create(:ai_agent_knowledge_source, ai_agent: ai_agent)
    product = create(:ai_agent_product, ai_agent: ai_agent)

    delete "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}", headers: admin.create_new_auth_token, as: :json

    expect(AiAgent::KnowledgeSource.exists?(source.id)).to be(false)
    expect(AiAgent::Product.exists?(product.id)).to be(false)
  end
end
