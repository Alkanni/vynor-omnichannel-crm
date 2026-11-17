require 'administrate/field/base'

# The account's feature flags a super admin can switch: premium, internal and deprecated features are left out.
# The form posts them as `enabled_features[<name>]`, read by SuperAdmin::AccountsController.
class AccountFeaturesField < Administrate::Field::Base
  def self.shown_feature_names(features)
    SuperAdmin::AccountFeaturesHelper.partition_features(features).first.keys.map(&:first)
  end

  # [[name, display name], enabled] pairs, sorted by display name.
  def features
    SuperAdmin::AccountFeaturesHelper.partition_features(data).first
  end
end
