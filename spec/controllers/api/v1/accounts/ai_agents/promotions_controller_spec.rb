require 'rails_helper'

RSpec.describe 'AI Agent promotions API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:ai_agent) { create(:ai_agent, account: account, timezone: 'Asia/Jakarta') }
  let(:other_ai_agent) { create(:ai_agent, account: account) }
  let(:product) { create(:ai_agent_product, ai_agent: ai_agent, name: 'Stabill') }
  let(:base_url) { "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/promotions" }

  # 10:00 on 25 November 2026 in Asia/Jakarta.
  before { travel_to(Time.utc(2026, 11, 25, 3, 0)) }

  describe 'GET index' do
    it 'returns the promotions of the AI agent, newest first, with their status today and products, filtered by status and title' do
      active = create(:ai_agent_promotion, ai_agent: ai_agent, title: 'Diskon Stabill', ends_on: Date.new(2026, 11, 25), products: [product])
      scheduled = create(:ai_agent_promotion, ai_agent: ai_agent, title: 'Akhir tahun', starts_on: Date.new(2026, 11, 26))
      archived = create(:ai_agent_promotion, ai_agent: ai_agent, title: 'Oktober', ends_on: Date.new(2026, 11, 24))
      create(:ai_agent_promotion, ai_agent: other_ai_agent)

      get base_url, headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['payload'].pluck('id', 'status'))
        .to eq([[archived.id, 'archived'], [scheduled.id, 'scheduled'], [active.id, 'active']])
      expect(response.parsed_body['payload'].last).to include('title' => 'Diskon Stabill', 'starts_on' => nil, 'ends_on' => '2026-11-25',
                                                              'products' => [{ 'id' => product.id, 'name' => 'Stabill' }])

      { 'active' => active, 'scheduled' => scheduled, 'archived' => archived }.each do |status, promotion|
        get base_url, params: { status: status }, headers: admin.create_new_auth_token, as: :json
        expect(response.parsed_body['payload'].pluck('id')).to eq([promotion.id])
      end

      get base_url, params: { q: 'stabill' }, headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['payload'].pluck('id')).to eq([active.id])
    end

    it 'rejects an unknown status' do
      get base_url, params: { status: 'expired' }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'returns unauthorized for agents' do
      get base_url, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST create' do
    it 'creates a promotion linked to products of the AI agent' do
      post base_url, params: { title: 'Diskon Stabill', description: 'Stabill Rp80.000', starts_on: '2026-11-01', ends_on: '2026-11-30',
                               product_ids: [product.id] },
                     headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      promotion = ai_agent.promotions.last
      expect(promotion).to have_attributes(title: 'Diskon Stabill', starts_on: Date.new(2026, 11, 1), ends_on: Date.new(2026, 11, 30),
                                           account_id: account.id, products: [product])
      expect(response.parsed_body).to include('status' => 'active', 'products' => [{ 'id' => product.id, 'name' => 'Stabill' }])
    end

    it 'creates a promotion without dates or products, valid with no end' do
      post base_url, params: { title: 'Gratis cuci', description: 'Untuk servis besar', starts_on: '', ends_on: '', product_ids: [] },
                     headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(ai_agent.promotions.last).to have_attributes(starts_on: nil, ends_on: nil, products: [])
    end

    it 'rejects a blank title or details, and an end date before the start date' do
      post base_url, params: { title: '', description: '', starts_on: '2026-11-30', ends_on: '2026-11-01' },
                     headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['attributes']).to contain_exactly('title', 'description', 'ends_on')
    end

    it 'rejects products of another AI agent' do
      foreign = create(:ai_agent_product, ai_agent: other_ai_agent)

      post base_url, params: { title: 'Diskon', description: 'Rp80.000', product_ids: [product.id, foreign.id] },
                     headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('Select products of this AI agent')
      expect(ai_agent.promotions.count).to eq(0)
    end

    it 'returns unauthorized for agents' do
      post base_url, params: { title: 'Diskon', description: 'Rp80.000' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(AiAgent::Promotion.count).to eq(0)
    end
  end

  describe 'PATCH update' do
    let(:promotion) { create(:ai_agent_promotion, ai_agent: ai_agent, ends_on: Date.new(2026, 11, 24), products: [product]) }

    it 'makes an archived promotion active again with a later end date, or none' do
      patch "#{base_url}/#{promotion.id}", params: { ends_on: '2026-12-31' }, headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body).to include('status' => 'active', 'ends_on' => '2026-12-31')

      patch "#{base_url}/#{promotion.id}", params: { ends_on: '' }, headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body).to include('status' => 'active', 'ends_on' => nil)
      expect(promotion.reload.products).to eq([product])
    end

    it 'replaces the products when product_ids is sent' do
      other = create(:ai_agent_product, ai_agent: ai_agent)

      patch "#{base_url}/#{promotion.id}", params: { product_ids: [other.id] }, headers: admin.create_new_auth_token, as: :json

      expect(promotion.reload.products).to eq([other])
    end

    it 'keeps the promotion as it was when its update is rejected' do
      patch "#{base_url}/#{promotion.id}", params: { title: '', product_ids: [] }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(promotion.reload.products).to eq([product])
    end

    it 'returns not found for a promotion of another AI agent' do
      foreign = create(:ai_agent_promotion, ai_agent: other_ai_agent)

      patch "#{base_url}/#{foreign.id}", params: { title: 'Baru' }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'DELETE destroy' do
    it 'deletes the promotion and its links, keeping the products' do
      promotion = create(:ai_agent_promotion, ai_agent: ai_agent, products: [product])

      delete "#{base_url}/#{promotion.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(AiAgent::Promotion.exists?(promotion.id)).to be(false)
      expect(AiAgent::PromotionProduct.count).to eq(0)
      expect(AiAgent::Product.exists?(product.id)).to be(true)
    end
  end

  describe 'POST bulk_destroy' do
    it 'deletes only the selected promotions of this AI agent' do
      selected = create_list(:ai_agent_promotion, 2, ai_agent: ai_agent)
      kept = create(:ai_agent_promotion, ai_agent: ai_agent)
      foreign = create(:ai_agent_promotion, ai_agent: other_ai_agent)

      post "#{base_url}/bulk_destroy", params: { ids: selected.map(&:id) + [foreign.id] }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(ai_agent.promotions.pluck(:id)).to eq([kept.id])
      expect(AiAgent::Promotion.exists?(foreign.id)).to be(true)
    end

    it 'returns unauthorized for agents' do
      promotion = create(:ai_agent_promotion, ai_agent: ai_agent)

      post "#{base_url}/bulk_destroy", params: { ids: [promotion.id] }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(AiAgent::Promotion.exists?(promotion.id)).to be(true)
    end
  end
end
