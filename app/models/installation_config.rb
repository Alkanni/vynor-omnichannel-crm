# == Schema Information
#
# Table name: installation_configs
#
#  id               :bigint           not null, primary key
#  locked           :boolean          default(TRUE), not null
#  name             :string           not null
#  serialized_value :jsonb            not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#
# Indexes
#
#  index_installation_configs_on_name                 (name) UNIQUE
#  index_installation_configs_on_name_and_created_at  (name,created_at) UNIQUE
#
class InstallationConfig < ApplicationRecord
  CAPTAIN_LLM_CONFIG_KEYS = %w[
    CAPTAIN_OPEN_AI_API_KEY
    CAPTAIN_OPEN_AI_ENDPOINT
    CAPTAIN_OPEN_AI_MODEL
  ].freeze

  RESTART_REQUIRED_CONFIG_KEYS = (CAPTAIN_LLM_CONFIG_KEYS + %w[
    LANGFUSE_BASE_URL
    LANGFUSE_PUBLIC_KEY
    LANGFUSE_SECRET_KEY
    OTEL_PROVIDER
  ]).freeze

  # https://stackoverflow.com/questions/72970170/upgrading-to-rails-6-1-6-1-causes-psychdisallowedclass-tried-to-load-unspecif
  # https://discuss.rubyonrails.org/t/cve-2022-32224-possible-rce-escalation-bug-with-serialized-columns-in-active-record/81017
  # FIX ME : fixes breakage of installation config. we need to migrate.
  # Fix configuration in application.rb
  serialize :serialized_value, coder: YAML, type: ActiveSupport::HashWithIndifferentAccess, default: {}.with_indifferent_access

  before_validation :set_lock
  validates :name, presence: true
  validate :saml_sso_users_check, if: -> { name == 'ENABLE_SAML_SSO_LOGIN' }
  validate :ai_agent_max_distance_check, if: -> { name == 'AI_AGENT_EMBEDDING_MAX_DISTANCE' }
  validate :ai_agent_web_search_budget_check, if: -> { name == 'AI_AGENT_WEB_SEARCH_MONTHLY_BUDGET' }

  # TODO: Get rid of default scope
  # https://stackoverflow.com/a/1834250/939299
  default_scope { order(created_at: :desc) }
  scope :editable, -> { where(locked: false) }

  after_commit :clear_cache

  def value
    serialized_value[:value]
  end

  def value=(value_to_assigned)
    self.serialized_value = {
      value: value_to_assigned
    }.with_indifferent_access
  end

  private

  def set_lock
    self.locked = true if locked.nil?
  end

  def clear_cache
    GlobalConfig.clear_cache
  end

  def saml_sso_users_check
    return unless value == false || value == 'false'
    return unless User.exists?(provider: 'saml')

    errors.add(:base, 'Cannot disable SAML SSO login while users are using SAML authentication')
  end

  # Cosine distance runs from 0 (same direction) to 2 (opposite).
  def ai_agent_max_distance_check
    return if value.blank?

    distance = Float(value, exception: false)
    return if distance&.positive? && distance <= 2

    errors.add(:base, 'AI Agent Max Embedding Distance must be a number greater than 0 and at most 2')
  end

  # Blank means the default budget (see AiAgents::WebSearch.monthly_budget).
  def ai_agent_web_search_budget_check
    return if value.blank?

    budget = Float(value, exception: false)
    return if budget && budget >= 0

    errors.add(:base, 'AI Agent Web Search Monthly Budget must be a number of US dollars, 0 or more')
  end
end
