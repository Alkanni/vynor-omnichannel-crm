# Switches one feature on or off for every account, from Super Admin → Settings → Features.
# Only the features AccountFeaturesField shows can be switched; every other flag of an account stays as it is.
class SuperAdmin::AccountFeaturesController < SuperAdmin::ApplicationController
  ENABLED_VALUES = { 'true' => true, 'false' => false }.freeze

  def update
    name, display_name = AccountFeaturesField.shown_features.find { |feature_name, _| feature_name == params[:name] }
    return head :unprocessable_entity if name.nil? || !ENABLED_VALUES.key?(params[:enabled])

    enabled = ENABLED_VALUES.fetch(params[:enabled])
    Account.transaction do
      Account.find_each do |account|
        enabled ? account.enable_features(name) : account.disable_features(name)
        account.save!
      end
    end

    notice_key = enabled ? 'enabled_notice' : 'disabled_notice'
    redirect_to super_admin_settings_path, notice: t("super_admin.settings.account_features.#{notice_key}", feature: display_name || name)
  end
end
