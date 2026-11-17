require 'rails_helper'

RSpec.describe 'Super Admin Application Config API', type: :request do
  let(:super_admin) { create(:super_admin) }

  describe 'GET /super_admin/app_config' do
    context 'when it is an unauthenticated super admin' do
      it 'returns unauthorized' do
        get '/super_admin/app_config'
        expect(response).to have_http_status(:redirect)
      end
    end

    context 'when it is an authenticated super admin' do
      let!(:config) { create(:installation_config, { name: 'FB_APP_ID', value: 'TESTVALUE' }) }

      it 'shows the app_config page' do
        sign_in(super_admin, scope: :super_admin)
        get '/super_admin/app_config?config=facebook'
        expect(response).to have_http_status(:success)
        expect(response.body).to include(config.value)
      end

      it 'shows the AI Agent request log settings on the captain page' do
        sign_in(super_admin, scope: :super_admin)
        get '/super_admin/app_config?config=captain'

        expect(response).to have_http_status(:success)
        expect(response.body).to include('app_config[AI_AGENT_REQUEST_LOG_ENABLED]', 'app_config[AI_AGENT_REQUEST_LOG_MASK_PII]')
      end
    end
  end

  describe 'POST /super_admin/app_config' do
    context 'when it is an unauthenticated super admin' do
      it 'returns unauthorized' do
        post '/super_admin/app_config', params: { app_config: { TESTKEY: 'TESTVALUE' } }
        expect(response).to have_http_status(:redirect)
      end
    end

    context 'when it is an aunthenticated super admin' do
      it 'shows the app_config page' do
        sign_in(super_admin, scope: :super_admin)
        post '/super_admin/app_config?config=facebook', params: { app_config: { FB_APP_ID: 'FB_APP_ID' } }

        expect(response).to have_http_status(:found)
        expect(response).to redirect_to(super_admin_settings_path)
        expect(flash[:notice]).to be_present
        expect(flash[:alert]).to be_blank
        expect(flash[:success]).to be_blank

        config = GlobalConfig.get('FB_APP_ID')
        expect(config['FB_APP_ID']).to eq('FB_APP_ID')
      end

      it 'asks admins to restart web and worker processes for runtime config changes' do
        sign_in(super_admin, scope: :super_admin)
        post '/super_admin/app_config?config=captain', params: { app_config: { CAPTAIN_OPEN_AI_ENDPOINT: 'https://api.openai.com' } }

        expect(response).to have_http_status(:found)
        expect(response).to redirect_to(super_admin_settings_path)
        expect(flash[:success]).to be_present
        expect(flash[:alert]).to be_blank
        expect(flash[:notice]).to be_blank
      end

      it 'saves the AI Agent request log settings as the request recorder reads them' do
        sign_in(super_admin, scope: :super_admin)
        post '/super_admin/app_config?config=captain',
             params: { app_config: { AI_AGENT_REQUEST_LOG_ENABLED: 'true', AI_AGENT_REQUEST_LOG_MASK_PII: 'false' } }

        expect(response).to redirect_to(super_admin_settings_path)
        expect(AiAgents::RequestRecorder).to be_enabled
        expect(AiAgents::RequestRecorder).not_to be_mask_pii
      end

      it 'rejects an AI Agent max embedding distance that is not a cosine distance' do
        sign_in(super_admin, scope: :super_admin)
        post '/super_admin/app_config?config=captain', params: { app_config: { AI_AGENT_EMBEDDING_MAX_DISTANCE: 'abc' } }

        expect(response).to redirect_to(super_admin_app_config_path(config: 'captain'))
        expect(flash[:alert]).to eq('AI Agent Max Embedding Distance must be a number greater than 0 and at most 2')
        expect(InstallationConfig.find_by(name: 'AI_AGENT_EMBEDDING_MAX_DISTANCE')&.value).to be_nil
      end
    end
  end
end
