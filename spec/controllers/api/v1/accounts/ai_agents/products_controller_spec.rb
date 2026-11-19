require 'rails_helper'

RSpec.describe 'AI Agent products API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:ai_agent) { create(:ai_agent, account: account) }
  let(:base_url) { "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/products" }

  describe 'GET index' do
    it 'returns the products of the AI agent, newest first, filtered by name, with the currency of their prices' do
      stabill = create(:ai_agent_product, ai_agent: ai_agent, name: 'Stabill')
      jok = create(:ai_agent_product, ai_agent: ai_agent, name: 'Jok Mobil Lederlux', price: nil, weight: nil, stock: nil)
      create(:ai_agent_product, ai_agent: create(:ai_agent, account: account), name: 'Jok Lain')

      get base_url, headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['payload'].pluck('id')).to eq([jok.id, stabill.id])
      expect(response.parsed_body['payload'].first).to include('price' => nil, 'weight' => nil, 'stock' => nil)
      expect(response.parsed_body['currency']).to eq('IDR')

      get base_url, params: { q: 'jok' }, headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['payload'].pluck('id')).to eq([jok.id])
    end

    it 'returns unauthorized for agents' do
      get base_url, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST create' do
    it 'creates a product with an image' do
      image = fixture_file_upload(Rails.root.join('spec/assets/avatar.png'), 'image/png')

      post base_url, params: { name: 'Balance arm', description: 'Alat untuk balancing', price: '4750000', weight: '100', stock: '100',
                               image: image },
                     headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      product = ai_agent.products.last
      expect(product).to have_attributes(name: 'Balance arm', price: 4_750_000, weight: 100, stock: 100, account_id: account.id)
      expect(product.image).to be_attached
      expect(response.parsed_body['image_url']).to be_present
    end

    it 'creates a product without price, weight, and stock' do
      post base_url, params: { name: 'Konsultasi', price: '', weight: '', stock: '' }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(ai_agent.products.last).to have_attributes(name: 'Konsultasi', price: nil, weight: nil, stock: nil)
      expect(response.parsed_body).to include('price' => nil, 'weight' => nil, 'stock' => nil)
    end

    it 'rejects invalid products' do
      post base_url, params: { name: '', price: '-5' }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['attributes']).to contain_exactly('name', 'price')
    end

    it 'rejects non image files' do
      file = fixture_file_upload(Rails.root.join('spec/assets/sample.pdf'), 'application/pdf')

      post base_url, params: { name: 'Stabill', image: file }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
      expect(ai_agent.products.count).to eq(0)
    end
  end

  describe 'PATCH update' do
    it 'updates the product' do
      product = create(:ai_agent_product, ai_agent: ai_agent)

      patch "#{base_url}/#{product.id}", params: { stock: '5', price: '1600000.50' }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(product.reload).to have_attributes(stock: 5, price: BigDecimal('1600000.50'))

      patch "#{base_url}/#{product.id}", params: { stock: '', weight: '' }, headers: admin.create_new_auth_token

      expect(product.reload).to have_attributes(stock: nil, weight: nil, price: BigDecimal('1600000.50'))
    end

    it 'returns not found for a product of another AI agent' do
      product = create(:ai_agent_product, ai_agent: create(:ai_agent, account: account))

      patch "#{base_url}/#{product.id}", params: { stock: '5' }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'DELETE destroy' do
    it 'deletes the product' do
      product = create(:ai_agent_product, ai_agent: ai_agent)

      delete "#{base_url}/#{product.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(AiAgent::Product.exists?(product.id)).to be(false)
    end
  end

  describe 'POST bulk_destroy' do
    it 'deletes only the selected products of this AI agent' do
      selected = create_list(:ai_agent_product, 2, ai_agent: ai_agent)
      kept = create(:ai_agent_product, ai_agent: ai_agent)
      foreign = create(:ai_agent_product, ai_agent: create(:ai_agent, account: account))

      post "#{base_url}/bulk_destroy", params: { ids: selected.map(&:id) + [foreign.id] }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(ai_agent.products.pluck(:id)).to eq([kept.id])
      expect(AiAgent::Product.exists?(foreign.id)).to be(true)
    end

    it 'requires ids' do
      post "#{base_url}/bulk_destroy", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'returns unauthorized for agents' do
      product = create(:ai_agent_product, ai_agent: ai_agent)

      post "#{base_url}/bulk_destroy", params: { ids: [product.id] }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(AiAgent::Product.exists?(product.id)).to be(true)
    end
  end
end
