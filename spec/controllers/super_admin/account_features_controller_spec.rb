require 'rails_helper'

RSpec.describe 'Super Admin account features', type: :request do
  let!(:super_admin) { create(:super_admin) }
  let!(:account) { create(:account) }
  let!(:other_account) { create(:account) }
  let(:premium_feature) { SuperAdmin::AccountFeaturesHelper.account_premium_features.first }

  describe 'GET /super_admin/settings' do
    it 'lists the switchable features with how many accounts have each one on' do
      account.enable_features!(:whatsapp_campaign)
      sign_in(super_admin, scope: :super_admin)

      get '/super_admin/settings'

      document = Nokogiri::HTML(response.body)
      row = document.at_css('[data-account-feature="whatsapp_campaign"]')
      expect(response).to have_http_status(:success)
      expect(row.text.squish).to include('WhatsApp Campaign', 'Enabled for 1 of 2 accounts', 'Enable for all', 'Disable for all')
      expect(document.css('[data-account-feature]').size).to eq(AccountFeaturesField.shown_features.size)
      expect(document.at_css("[data-account-feature=\"#{premium_feature}\"]")).to be_nil
    end
  end

  describe 'PATCH /super_admin/account_features/:name' do
    it 'redirects to the sign in page when no super admin is signed in' do
      patch '/super_admin/account_features/whatsapp_campaign', params: { enabled: 'true' }

      expect(response).to have_http_status(:redirect)
      expect(account.reload.feature_enabled?(:whatsapp_campaign)).to be false
    end

    context 'when a super admin is signed in' do
      before { sign_in(super_admin, scope: :super_admin) }

      it 'turns the feature on for every account without changing their other flags' do
        account.enable_features!(premium_feature)
        flags_before = [account, other_account].map { |a| a.reload.all_features.except('whatsapp_campaign') }

        patch '/super_admin/account_features/whatsapp_campaign', params: { enabled: 'true' }

        expect(response).to redirect_to('/super_admin/settings')
        expect(flash[:notice]).to eq('WhatsApp Campaign is now enabled for all accounts.')
        [account, other_account].each(&:reload)
        expect([account, other_account].map { |a| a.feature_enabled?(:whatsapp_campaign) }).to eq([true, true])
        expect([account, other_account].map { |a| a.all_features.except('whatsapp_campaign') }).to eq(flags_before)
        expect(account.feature_enabled?(premium_feature)).to be true
      end

      it 'turns the feature off for every account without changing their other flags' do
        [account, other_account].each { |a| a.enable_features!(:whatsapp_campaign, premium_feature) }
        flags_before = [account, other_account].map { |a| a.reload.all_features.except('whatsapp_campaign') }

        patch '/super_admin/account_features/whatsapp_campaign', params: { enabled: 'false' }

        expect(flash[:notice]).to eq('WhatsApp Campaign is now disabled for all accounts.')
        [account, other_account].each(&:reload)
        expect([account, other_account].map { |a| a.feature_enabled?(:whatsapp_campaign) }).to eq([false, false])
        expect([account, other_account].map { |a| a.all_features.except('whatsapp_campaign') }).to eq(flags_before)
      end

      it 'refuses a feature the settings page does not list' do
        patch "/super_admin/account_features/#{premium_feature}", params: { enabled: 'true' }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(account.reload.feature_enabled?(premium_feature)).to be false
      end

      it 'refuses an unknown feature' do
        patch '/super_admin/account_features/not_a_feature', params: { enabled: 'true' }

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'refuses an enabled value other than true or false' do
        patch '/super_admin/account_features/whatsapp_campaign', params: { enabled: '1' }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(account.reload.feature_enabled?(:whatsapp_campaign)).to be false
      end

      it 'shows the same state on the account edit page afterwards' do
        patch '/super_admin/account_features/whatsapp_campaign', params: { enabled: 'true' }

        get "/super_admin/accounts/#{account.id}/edit"

        checkbox = Nokogiri::HTML(response.body).at_css('input[name="enabled_features[whatsapp_campaign]"]')
        expect(checkbox['checked']).to be_present
      end
    end
  end
end
