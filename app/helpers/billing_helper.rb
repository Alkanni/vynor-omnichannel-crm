module BillingHelper
  private

  def default_plan?(account)
    installation_config = InstallationConfig.find_by(name: 'CHATWOOT_CLOUD_PLANS')
    default_plan = installation_config&.value&.first

    # Return false if not plans are configured, so that no checks are enforced
    return false if default_plan.blank?

    account.custom_attributes['plan_name'].nil? || account.custom_attributes['plan_name'] == default_plan['name']
  end
end
