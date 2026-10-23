# == Schema Information
#
# Table name: ai_agent_integrations
#
#  id               :bigint           not null, primary key
#  credentials      :text
#  integration_type :string           not null
#  settings         :jsonb            not null
#  status           :integer          default("connected"), not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  account_id       :bigint           not null
#  ai_agent_id      :bigint           not null
#
# Indexes
#
#  index_ai_agent_integrations_on_account_id      (account_id)
#  index_ai_agent_integrations_on_agent_and_type  (ai_agent_id,integration_type) UNIQUE
#
class AiAgent::Integration < ApplicationRecord
  TYPES = %w[google_sheets].freeze

  belongs_to :account
  belongs_to :ai_agent

  # OAuth tokens: never rendered, always encrypted (connecting requires Active Record encryption keys).
  serialize :credentials, coder: JSON
  encrypts :credentials

  enum :status, { connected: 0, needs_reconnect: 1 }

  before_validation :assign_account

  validates :integration_type, inclusion: { in: TYPES }, uniqueness: { scope: :ai_agent_id }

  # Settings an AI reply needs to write rows: a header row to fill and a condition for when to write.
  def writable?
    connected? && settings['columns'].present? && settings['when_to_write'].present?
  end

  private

  def assign_account
    self.account_id = ai_agent&.account_id
  end
end
