class SuperAdmin::SettingsController < SuperAdmin::ApplicationController
  # The features a super admin can switch for all accounts, with how many accounts have each one on.
  def show
    account_flags = Account.all.map(&:all_features)
    @accounts_count = account_flags.size
    @account_features = AccountFeaturesField.shown_features.map do |name, display_name|
      { name: name, display_name: display_name || name, enabled_count: account_flags.count { |flags| flags[name] } }
    end
  end

  def refresh
    Internal::CheckNewVersionsJob.perform_now
    # rubocop:disable Rails/I18nLocaleTexts
    redirect_to super_admin_settings_path, notice: 'Instance status refreshed'
    # rubocop:enable Rails/I18nLocaleTexts
  end
end
