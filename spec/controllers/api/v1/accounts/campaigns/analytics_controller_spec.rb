require 'rails_helper'

RSpec.describe 'Campaign analytics API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:campaign) { create(:campaign, account: account) }
  let(:base_url) { "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}/analytics" }

  before do
    create(:campaign_recipient, campaign: campaign, status: :queued)
    create(:campaign_recipient, campaign: campaign, status: :sent, source_id: 'wamid.sent')
    create(:campaign_recipient, campaign: campaign, status: :delivered, source_id: 'wamid.delivered')
    create(:campaign_recipient, campaign: campaign, status: :read, source_id: 'wamid.read', message_content: 'Hi there')
    create(:campaign_recipient, campaign: campaign, status: :failed, source_id: 'wamid.failed', error_code: '131026',
                                error_title: 'Message undeliverable')
    create(:campaign_recipient, campaign: campaign, status: :failed, error_message: '(#131030) Recipient phone number not in allowed list')
    create(:campaign_recipient, campaign: campaign, status: :skipped, error_message: 'Phone number and BSUID are missing')
  end

  describe 'GET /api/v1/accounts/{account.id}/campaigns/:campaign_id/analytics/metrics' do
    it 'returns unauthorized for unauthenticated users' do
      get "#{base_url}/metrics"

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns unauthorized for agents' do
      get "#{base_url}/metrics", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns not found for a campaign outside the account' do
      other_campaign = create(:campaign, account: create(:account))
      other_campaign.update!(display_id: campaign.display_id + 1)

      get "/api/v1/accounts/#{account.id}/campaigns/#{other_campaign.display_id}/analytics/metrics",
          headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'counts the recipients, sent covering every message WhatsApp accepted and delivered including read' do
      get "#{base_url}/metrics", headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to eq(
        'audience' => 7, 'sent' => 4, 'delivered' => 2, 'read' => 1, 'failed' => 2, 'skipped' => 1,
        'status_counts' => { 'queued' => 1, 'skipped' => 1, 'sent' => 1, 'delivered' => 1, 'read' => 1, 'failed' => 2 }
      )
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/campaigns/:campaign_id/analytics/contacts' do
    it 'returns unauthorized for agents' do
      get "#{base_url}/contacts", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'lists every recipient with its contact and delivery details' do
      get "#{base_url}/contacts", headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['meta']).to include('total_count' => 7)
      read_recipient = body['payload'].find { |recipient| recipient['status'] == 'read' }
      expect(read_recipient).to include('message_content' => 'Hi there')
      expect(read_recipient['contact'].keys).to contain_exactly('id', 'name', 'phone_number')
    end

    it 'filters by status' do
      get "#{base_url}/contacts", params: { status: 'failed' }, headers: administrator.create_new_auth_token

      expect(response.parsed_body['payload']).to contain_exactly(
        include('status' => 'failed', 'error_code' => '131026', 'error_title' => 'Message undeliverable'),
        include('status' => 'failed', 'error_message' => '(#131030) Recipient phone number not in allowed list')
      )
      expect(response.parsed_body['meta']).to include('total_count' => 2)
    end

    it 'pages 25 recipients at a time' do
      create_list(:campaign_recipient, 20, campaign: campaign)

      get "#{base_url}/contacts", params: { page: 2 }, headers: administrator.create_new_auth_token

      expect(response.parsed_body['payload'].size).to eq(2)
      expect(response.parsed_body['meta']).to include('total_count' => 27, 'current_page' => 2)
    end

    it 'rejects an unknown status' do
      get "#{base_url}/contacts", params: { status: 'bounced' }, headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
