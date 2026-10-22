# == Schema Information
#
# Table name: ai_agents
#
#  id                         :bigint           not null, primary key
#  allowed_label_ids          :jsonb            not null
#  behavior                   :text
#  context_limit              :integer          default(40), not null
#  history_limit              :integer          default(30), not null
#  ignore_team_handoff        :boolean          default(FALSE), not null
#  label_conditions           :text
#  message_await              :integer          default(10), not null
#  message_limit              :integer          default(10), not null
#  model                      :string           not null
#  name                       :string           not null
#  pending_assigned_message   :string
#  pending_unassigned_message :string
#  read_file_limit            :integer          default(3), not null
#  session_only_memory        :boolean          default(FALSE), not null
#  silent_handoff             :boolean          default(FALSE), not null
#  stop_ai_after_handoff      :boolean          default(TRUE), not null
#  temperature                :string           default("balanced"), not null
#  timezone                   :string           default("Asia/Jakarta"), not null
#  transfer_conditions        :text
#  watcher_enabled            :boolean          default(FALSE), not null
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

  belongs_to :account

  attribute :model, :string, default: -> { Llm::Models.default_model_for(LLM_FEATURE) }

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
  validate :model_supported
  validate :allowed_labels_belong_to_account

  def duplicate!
    copy = dup
    copy.name = I18n.t('ai_agents.duplicate_name', name: name).truncate(255)
    copy.save!
    copy
  end

  private

  def model_supported
    config = Llm::Models.model_config(model)
    return if Llm::Models.valid_model_for?(LLM_FEATURE, model) && !config['coming_soon']

    errors.add(:model, :inclusion)
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
