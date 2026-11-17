require 'administrate/field/base'

# The account's feature flags a super admin can switch: premium, internal and deprecated features are left out.
# The form posts them as `enabled_features[<name>]`, read by SuperAdmin::AccountsController.
class AccountFeaturesField < Administrate::Field::Base
  # [name, display name] pairs of the features a super admin can switch, sorted by display name.
  def self.shown_features
    all_off = Featurable::FEATURE_LIST.pluck('name').index_with(false)
    SuperAdmin::AccountFeaturesHelper.partition_features(all_off).first.keys
  end

  def self.shown_feature_names
    shown_features.map(&:first)
  end

  # [[name, display name], enabled] pairs, sorted by display name.
  def features
    SuperAdmin::AccountFeaturesHelper.partition_features(data).first
  end
end
