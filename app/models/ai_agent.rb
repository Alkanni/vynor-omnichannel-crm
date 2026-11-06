# == Schema Information
#
# Table name: ai_agents
#
#  id                         :bigint           not null, primary key
#  allowed_label_ids          :jsonb            not null
#  allowed_topics             :text
#  behavior                   :text
#  business_description       :text
#  clarification_message      :text
#  context_limit              :integer          default(8), not null
#  disallowed_topics          :text
#  history_limit              :integer          default(30), not null
#  ignore_team_handoff        :boolean          default(FALSE), not null
#  knowledge_gap_message      :text
#  label_conditions           :text
#  message_await              :integer          default(10), not null
#  message_limit              :integer          default(10), not null
#  model                      :string           not null
#  name                       :string           not null
#  off_topic_message          :text
#  pending_assigned_message   :string
#  pending_unassigned_message :string
#  read_file_limit            :integer          default(3), not null
#  scope_mode                 :string           default("off"), not null
#  scope_policy_version       :integer          default(0), not null
#  session_only_memory        :boolean          default(FALSE), not null
#  silent_handoff             :boolean          default(FALSE), not null
#  stop_ai_after_handoff      :boolean          default(TRUE), not null
#  temperature                :string           default("balanced"), not null
#  timezone                   :string           default("Asia/Jakarta"), not null
#  trained_at                 :datetime
#  training_error             :string
#  training_failed_at         :datetime
#  transfer_conditions        :text
#  watcher_enabled            :boolean          default(FALSE), not null
#  web_search_domains         :text
#  web_search_enabled         :boolean          default(FALSE), not null
#  welcome_message            :text
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  account_id                 :bigint           not null
#
# Indexes
#
#  index_ai_agents_on_account_id  (account_id)
#
class AiAgent < ApplicationRecord
  LLM_FEATURE = 'assistant'.freeze
  TEMPERATURES = %w[precise balanced creative].freeze
  SCOPE_MODES = %w[off strict].freeze
  SCOPE_POLICY_ATTRIBUTES = %w[
    scope_mode business_description allowed_topics disallowed_topics off_topic_message clarification_message knowledge_gap_message
    web_search_enabled web_search_domains
  ].freeze
  # A host name such as kompas.com or otomotif.kompas.com, as the web search providers take it (see AiAgents::WebSearch).
  WEB_SEARCH_DOMAIN = /\A(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}\z/i
  TRAINING_DELAY = 10.seconds

  belongs_to :account
  has_many :knowledge_sources, class_name: 'AiAgent::KnowledgeSource', dependent: :destroy
  has_many :products, class_name: 'AiAgent::Product', dependent: :destroy
  has_many :knowledge_chunks, class_name: 'AiAgent::KnowledgeChunk', dependent: :delete_all
  has_many :reply_traces, class_name: 'AiAgent::ReplyTrace', dependent: :delete_all
  has_many :ai_agent_inboxes, dependent: :destroy
  has_one :google_sheets_integration, -> { where(integration_type: 'google_sheets') },
          class_name: 'AiAgent::Integration', dependent: :destroy, inverse_of: :ai_agent
  has_many :inboxes, through: :ai_agent_inboxes
  has_many :messages, as: :sender, dependent: :nullify
  has_many :assigned_conversations, class_name: 'Conversation',
                                    foreign_key: :assignee_agent_bot_id,
                                    dependent: :nullify,
                                    as: :ai_assignee,
                                    inverse_of: :ai_assignee

  attribute :model, :string, default: -> { default_model }

  # A blank field is nil, because the settings form sends unset fields as empty strings and that is no policy change.
  normalizes :business_description, :allowed_topics, :disallowed_topics, :off_topic_message, :clarification_message, :knowledge_gap_message,
             :web_search_domains, with: ->(text) { text.strip.presence }

  validates :name, presence: true, length: { maximum: 255 }
  validates :behavior, length: { maximum: 15_000 }
  validates :welcome_message, length: { maximum: 5_000 }
  validates :transfer_conditions, :label_conditions, length: { maximum: 3_000 }
  validates :pending_assigned_message, :pending_unassigned_message, length: { maximum: 200 }
  validates :history_limit, numericality: { only_integer: true, in: 1..100 }
  validates :read_file_limit, numericality: { only_integer: true, in: 0..10 }
  validates :context_limit, numericality: { only_integer: true, in: 1..100 }
  validates :message_await, numericality: { only_integer: true, in: 0..300 }
  validates :message_limit, numericality: { only_integer: true, in: 1..1000 }
  validates :temperature, inclusion: { in: TEMPERATURES }
  validates :timezone, inclusion: { in: TZInfo::Timezone.all_identifiers }
  validates :scope_mode, inclusion: { in: SCOPE_MODES }
  validates :business_description, :allowed_topics, :disallowed_topics, length: { maximum: 3_000 }
  validates :off_topic_message, :clarification_message, :knowledge_gap_message, length: { maximum: 1_000 }
  validates :business_description, :allowed_topics, :off_topic_message, :clarification_message, :knowledge_gap_message,
            presence: true, if: :scope_strict?
  validates :web_search_domains, length: { maximum: 1_000 }
  validate -> { errors.add(:web_search_enabled, I18n.t('ai_agents.web_search.errors.strict_scope_required')) },
           if: -> { web_search_enabled && !scope_strict? }
  validate -> { errors.add(:web_search_domains, :invalid) }, unless: -> { web_search_domain_list.all?(WEB_SEARCH_DOMAIN) }
  validate :model_supported
  validate :allowed_labels_belong_to_account

  before_update -> { self.scope_policy_version += 1 }, if: -> { changed.intersect?(SCOPE_POLICY_ATTRIBUTES) }

  # Gateway model IDs from Super Admin (AI_AGENT_MODELS, e.g. for 9router or OpenRouter) replace the built-in OpenAI models.
  def self.available_models
    gateway = gateway_models
    return gateway.map { |id| { id: id, display_name: id } } if gateway.any?

    Llm::Models.feature_config(LLM_FEATURE)[:models].reject { |config| config[:coming_soon] }.map { |config| config.slice(:id, :display_name) }
  end

  def self.default_model
    gateway_models.first || Llm::Models.default_model_for(LLM_FEATURE)
  end

  def self.gateway_models
    InstallationConfig.find_by(name: 'AI_AGENT_MODELS')&.value.to_s.split(',').map(&:strip).compact_blank.uniq
  end
  private_class_method :gateway_models

  def scope_strict?
    scope_mode == 'strict'
  end

  # Only strict agents can turn web search on, and it stays off for every agent while the web search API key is blank (see
  # AiAgents::WebSearch.configured?).
  def web_search?
    web_search_enabled && AiAgents::WebSearch.configured?
  end

  # The domains of web_search_domains, which may be separated by commas, spaces, or line breaks.
  def web_search_domain_list
    web_search_domains.to_s.split(/[\s,]+/).compact_blank
  end

  # The Business Scope Policy as the prompt block that replies and the scope check share.
  def business_scope
    policy = ["Business: #{business_description}", "Allowed topics: #{allowed_topics}"]
    policy << "Disallowed topics: #{disallowed_topics}" if disallowed_topics
    "<business_scope>\n#{policy.join("\n")}\n</business_scope>"
  end

  def duplicate!
    transaction do
      copy = dup
      copy.name = I18n.t('ai_agents.duplicate_name', name: name).truncate(255)
      copy.assign_attributes(trained_at: nil, training_error: nil, training_failed_at: nil)
      copy.save!
      knowledge_sources.each { |source| source.copy_to!(copy) }
      products.each { |product| product.copy_to!(copy) }
      copy
    end
  end

  # Knowledge changes arrive in bursts (e.g. a batch of website links finishing), so only one
  # indexing job is queued until it starts; see AiAgents::IndexKnowledgeJob.
  def schedule_training
    return unless Redis::Alfred.set(format(Redis::Alfred::AI_AGENT_TRAINING_SCHEDULED, id: id), 1, nx: true, ex: 1.hour)

    AiAgents::IndexKnowledgeJob.set(wait: TRAINING_DELAY).perform_later(self)
  end

  def push_event_data
    { id: id, name: name, avatar_url: '', type: 'ai_agent' }
  end

  def webhook_data
    { id: id, name: name, type: 'ai_agent' }
  end

  def knowledge_stats
    counts = knowledge_sources.group(:source_type).count
    characters = knowledge_characters

    {
      files: counts.fetch('file', 0),
      links: counts.fetch('website', 0),
      text_characters: characters.fetch('text', 0),
      qa_count: counts.fetch('qa', 0),
      qa_characters: characters.fetch('qa', 0),
      products: products.count,
      total_characters: characters.values.sum
    }
  end

  private

  # Characters per knowledge type; a Q&A also counts its question and products count name and description.
  def knowledge_characters
    characters = knowledge_sources.group(:source_type).sum(Arel.sql("char_length(coalesce(content, ''))"))
    characters['qa'] = characters.fetch('qa', 0) + knowledge_sources.qa.sum(Arel.sql('char_length(title)'))
    characters.merge('product' => products.sum(Arel.sql("char_length(name) + char_length(coalesce(description, ''))")))
  end

  def model_supported
    errors.add(:model, :inclusion) unless self.class.available_models.any? { |available| available[:id] == model }
  end

  def allowed_labels_belong_to_account
    unless allowed_label_ids.is_a?(Array) && allowed_label_ids.all?(Integer)
      errors.add(:allowed_label_ids, :invalid)
      return
    end
    return if allowed_label_ids.empty?
    return if account.labels.where(id: allowed_label_ids).count == allowed_label_ids.uniq.size

    errors.add(:allowed_label_ids, :invalid)
  end
end
