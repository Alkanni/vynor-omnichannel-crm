require 'rails_helper'

RSpec.describe 'AI Agents API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let!(:ai_agent) { create(:ai_agent, account: account) }

  describe 'GET /api/v1/accounts/{account.id}/ai_agents' do
    it 'returns unauthorized for unauthenticated users' do
      get "/api/v1/accounts/#{account.id}/ai_agents"

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns unauthorized for agents' do
      get "/api/v1/accounts/#{account.id}/ai_agents", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns only the AI agents of the account for administrators' do
      create(:ai_agent)

      get "/api/v1/accounts/#{account.id}/ai_agents", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['payload'].pluck('id')).to eq([ai_agent.id])
      expect(body['meta']['total_count']).to eq(1)
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/ai_agents/:id' do
    it 'returns the AI agent settings' do
      get "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include('id' => ai_agent.id, 'name' => ai_agent.name, 'temperature' => 'balanced', 'history_limit' => 30)
    end

    it 'returns not found for an AI agent of another account' do
      other_ai_agent = create(:ai_agent)

      get "/api/v1/accounts/#{account.id}/ai_agents/#{other_ai_agent.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/ai_agents' do
    it 'creates an AI agent with default settings' do
      expect do
        post "/api/v1/accounts/#{account.id}/ai_agents", params: { name: 'Grand Sehat AI' }, headers: admin.create_new_auth_token, as: :json
      end.to change(account.ai_agents, :count).by(1)

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include('name' => 'Grand Sehat AI', 'model' => Llm::Models.default_model_for('assistant'))
    end

    it 'returns unprocessable entity for invalid settings' do
      post "/api/v1/accounts/#{account.id}/ai_agents", params: { name: '' }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['attributes']).to include('name')
    end

    it 'returns unauthorized for agents' do
      expect do
        post "/api/v1/accounts/#{account.id}/ai_agents", params: { name: 'Bot' }, headers: agent.create_new_auth_token, as: :json
      end.not_to change(AiAgent, :count)

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/ai_agents/:id' do
    let(:label) { create(:label, account: account) }
    let(:params) do
      {
        behavior: 'Kamu adalah Customer Service', welcome_message: 'Halo Kak', transfer_conditions: 'Minta bicara dengan CS',
        stop_ai_after_handoff: false, silent_handoff: true, pending_assigned_message: 'Mohon tunggu',
        pending_unassigned_message: 'Sedang dicarikan CS', allowed_label_ids: [label.id], label_conditions: 'Label booking',
        model: 'gpt-4.1-mini', history_limit: 20, read_file_limit: 2, context_limit: 50, temperature: 'precise',
        message_await: 5, message_limit: 25, watcher_enabled: true, timezone: 'Asia/Makassar',
        session_only_memory: true, ignore_team_handoff: true
      }
    end

    it 'updates every General setting' do
      patch "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}", params: params, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(ai_agent.reload).to have_attributes(params)
    end

    it 'clears the allowed labels with an empty list' do
      ai_agent.update!(allowed_label_ids: [label.id])

      patch "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}",
            params: { allowed_label_ids: [] }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(ai_agent.reload.allowed_label_ids).to eq([])
    end

    it 'returns unprocessable entity for out of range values and foreign labels' do
      patch "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}",
            params: { history_limit: 500, model: 'unknown-model', timezone: 'Nowhere', allowed_label_ids: [create(:label).id],
                      behavior: 'a' * 15_001 },
            headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['attributes']).to contain_exactly('history_limit', 'model', 'timezone', 'allowed_label_ids', 'behavior')
      expect(ai_agent.reload.history_limit).to eq(30)
    end

    it 'returns unauthorized for agents' do
      patch "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}", params: { name: 'Changed' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(ai_agent.reload.name).not_to eq('Changed')
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/ai_agents/:id/duplicate' do
    it 'creates a copy with the same settings' do
      ai_agent.update!(welcome_message: 'Halo Kak', message_limit: 42)

      expect do
        post "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/duplicate", headers: admin.create_new_auth_token, as: :json
      end.to change(account.ai_agents, :count).by(1)

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include('name' => "#{ai_agent.name} (Copy)", 'welcome_message' => 'Halo Kak', 'message_limit' => 42)
    end

    it 'returns unauthorized for agents' do
      post "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/duplicate", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/ai_agents/:id' do
    it 'deletes the AI agent' do
      delete "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(AiAgent.exists?(ai_agent.id)).to be(false)

      get "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it 'returns unauthorized for agents' do
      delete "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(AiAgent.exists?(ai_agent.id)).to be(true)
    end
  end
end
