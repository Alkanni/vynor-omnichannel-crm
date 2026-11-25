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

    it 'shows how each source is indexed: chunk count, outdated after a change, and chunks of another embedding model' do
      create(:installation_config, name: 'AI_AGENT_EMBEDDING_MODEL', value: 'text-embedding-3-small')
      changed_text = create(:ai_agent_knowledge_source, ai_agent: ai_agent)
      new_text = create(:ai_agent_knowledge_source, ai_agent: ai_agent)
      [[text_source, 'text-embedding-3-small'], [text_source, 'old-model'], [changed_text, 'text-embedding-3-small']].each do |source, model|
        ai_agent.knowledge_chunks.create!(account: account, chunkable: source, chunkable_updated_at: source.updated_at,
                                          content: 'Bagian', embedding_model: model)
      end
      changed_text.update!(content: 'Isi baru')

      get base_url, params: { source_type: 'text' }, headers: admin.create_new_auth_token, as: :json

      indexes = response.parsed_body['payload'].to_h { |source| [source['id'], source['index'].except('indexed_at')] }
      expect(indexes).to eq(
        text_source.id => { 'status' => 'indexed', 'chunks' => 2, 'other_model_chunks' => 1 },
        changed_text.id => { 'status' => 'outdated', 'chunks' => 1, 'other_model_chunks' => 0 },
        new_text.id => { 'status' => 'not_indexed', 'chunks' => 0, 'other_model_chunks' => 0 }
      )
      expect(response.parsed_body['payload'].first['index']['indexed_at']).to be_a(Integer)
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

    it 'returns the source as outdated until it is indexed again' do
      ai_agent.knowledge_chunks.create!(account: account, chunkable: source, chunkable_updated_at: source.updated_at, content: 'Lama')

      patch "#{base_url}/#{source.id}", params: { content: 'Baru' }, headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['index']).to include('status' => 'outdated', 'chunks' => 1, 'other_model_chunks' => 0)
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
      create(:ai_agent_promotion, ai_agent: ai_agent)

      get "#{base_url}/stats", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to eq(
        'files' => 0, 'links' => 0, 'text_characters' => 5, 'qa_count' => 0, 'qa_characters' => 0, 'products' => 1, 'promotions' => 1,
        'total_characters' => 7
      )
    end
  end

  describe 'GET chunks' do
    let(:source) { create(:ai_agent_knowledge_source, ai_agent: ai_agent) }
    let(:other_source) { create(:ai_agent_knowledge_source, ai_agent: ai_agent) }

    before do
      [['Bagian satu', 'old-model', source], ['Bagian dua', 'text-embedding-3-small', source],
       ['Sumber lain', 'text-embedding-3-small', other_source]].each do |content, embedding_model, chunkable|
        ai_agent.knowledge_chunks.create!(account: account, chunkable: chunkable, chunkable_updated_at: chunkable.updated_at,
                                          content: content, embedding_model: embedding_model)
      end
    end

    it 'returns the chunks of the source in order, flagged by whether the current embedding model searches them' do
      create(:installation_config, name: 'AI_AGENT_EMBEDDING_MODEL', value: 'text-embedding-3-small')

      get "#{base_url}/#{source.id}/chunks", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['embedding_model']).to eq('text-embedding-3-small')
      expect(response.parsed_body['payload'].map { |chunk| chunk.slice('position', 'content', 'embedding_model', 'searchable') }).to eq(
        [{ 'position' => 1, 'content' => 'Bagian satu', 'embedding_model' => 'old-model', 'searchable' => false },
         { 'position' => 2, 'content' => 'Bagian dua', 'embedding_model' => 'text-embedding-3-small', 'searchable' => true }]
      )
      expect(response.parsed_body['payload'].pluck('indexed_at')).to all(be_a(Integer))
    end

    it 'flags every chunk as searchable when knowledge is searched by keywords' do
      get "#{base_url}/#{source.id}/chunks", headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['embedding_model']).to be_nil
      expect(response.parsed_body['payload'].pluck('searchable')).to eq([true, true])
    end

    it 'returns no chunks for a source that is not indexed yet' do
      new_source = create(:ai_agent_knowledge_source, ai_agent: ai_agent)

      get "#{base_url}/#{new_source.id}/chunks", headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['payload']).to eq([])
    end

    it 'does not return sources of another AI agent or to agents' do
      foreign_source = create(:ai_agent_knowledge_source, ai_agent: create(:ai_agent, account: account))

      get "#{base_url}/#{foreign_source.id}/chunks", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)

      get "#{base_url}/#{source.id}/chunks", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  it 'deletes knowledge sources and products with their AI agent' do
    source = create(:ai_agent_knowledge_source, ai_agent: ai_agent)
    product = create(:ai_agent_product, ai_agent: ai_agent)

    delete "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}", headers: admin.create_new_auth_token, as: :json

    expect(AiAgent::KnowledgeSource.exists?(source.id)).to be(false)
    expect(AiAgent::Product.exists?(product.id)).to be(false)
  end

  describe 'website sources' do
    before do
      allow(Resolv).to receive(:getaddresses).and_call_original
      allow(Resolv).to receive(:getaddresses).with('grandsehat.example.com').and_return(['93.184.216.34'])
    end

    it 'collects links from a site' do
      stub_request(:get, 'https://grandsehat.example.com/')
        .to_return(status: 200, body: '<a href="/promo">Promo</a>', headers: { 'content-type' => 'text/html' })
      stub_request(:get, 'https://grandsehat.example.com/sitemap.xml').to_return(status: 404)

      post "#{base_url}/collect_links", params: { url: 'https://grandsehat.example.com/' }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['links']).to eq(%w[https://grandsehat.example.com https://grandsehat.example.com/promo])
    end

    it 'rejects private addresses without fetching them' do
      post "#{base_url}/collect_links", params: { url: 'http://127.0.0.1:3000/' }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(a_request(:get, 'http://127.0.0.1:3000/')).not_to have_been_made
    end

    it 'adds links, skips links that already exist, and queues them for processing' do
      create(:ai_agent_knowledge_source, ai_agent: ai_agent, source_type: :website, external_url: 'https://grandsehat.example.com/promo')

      expect do
        post "#{base_url}/websites", params: { urls: %w[https://grandsehat.example.com/promo https://grandsehat.example.com/layanan] },
                                     headers: admin.create_new_auth_token, as: :json
      end.to have_enqueued_job(AiAgents::ProcessKnowledgeSourceJob).once

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload'].pluck('external_url', 'status')).to eq([['https://grandsehat.example.com/layanan', 'pending']])
    end

    it 'rejects invalid addresses and more than 300 links' do
      post "#{base_url}/websites", params: { urls: ['not a url'] }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)

      urls = (1..301).map { |n| "https://grandsehat.example.com/#{n}" }
      post "#{base_url}/websites", params: { urls: urls }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(ai_agent.knowledge_sources.count).to eq(0)
    end

    it 'syncs a link again' do
      source = create(:ai_agent_knowledge_source, ai_agent: ai_agent, source_type: :website, external_url: 'https://grandsehat.example.com',
                                                  content: 'Old', status: :failed)

      expect do
        post "#{base_url}/#{source.id}/resync", headers: admin.create_new_auth_token, as: :json
      end.to have_enqueued_job(AiAgents::ProcessKnowledgeSourceJob).with(source)

      expect(response.parsed_body['status']).to eq('pending')
    end

    it 'does not return page content in the list' do
      create(:ai_agent_knowledge_source, ai_agent: ai_agent, source_type: :website, external_url: 'https://grandsehat.example.com',
                                         content: 'Isi panjang', status: :ready)

      get base_url, params: { source_type: 'website' }, headers: admin.create_new_auth_token, as: :json

      source = response.parsed_body['payload'].first
      expect(source).not_to have_key('content')
      expect(source).to include('characters' => 11, 'external_url' => 'https://grandsehat.example.com', 'status' => 'ready')
    end
  end

  describe 'file sources' do
    it 'uploads a document and queues it for extraction' do
      file = fixture_file_upload(Rails.root.join('spec/assets/sample.pdf'), 'application/pdf')

      expect do
        post base_url, params: { source_type: 'file', file: file }, headers: admin.create_new_auth_token
      end.to have_enqueued_job(AiAgents::ProcessKnowledgeSourceJob)

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include('title' => 'sample.pdf', 'status' => 'pending', 'source_type' => 'file')
    end

    it 'rejects unsupported files' do
      file = fixture_file_upload(Rails.root.join('spec/assets/avatar.png'), 'image/png')

      post base_url, params: { source_type: 'file', file: file }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['attributes']).to eq(['file'])
    end

    it 'deletes several sources at once' do
      sources = create_list(:ai_agent_knowledge_source, 2, ai_agent: ai_agent)
      kept = create(:ai_agent_knowledge_source, ai_agent: ai_agent)

      post "#{base_url}/bulk_destroy", params: { ids: sources.map(&:id) }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(ai_agent.knowledge_sources.pluck(:id)).to eq([kept.id])
    end
  end
end
