# == Schema Information
#
# Table name: ai_agent_inboxes
#
#  id          :bigint           not null, primary key
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  ai_agent_id :bigint           not null
#  inbox_id    :bigint           not null
#
# Indexes
#
#  index_ai_agent_inboxes_on_ai_agent_id  (ai_agent_id)
#  index_ai_agent_inboxes_on_inbox_id     (inbox_id) UNIQUE
#
class AiAgentInbox < ApplicationRecord
  belongs_to :ai_agent
  belongs_to :inbox

  validate :inbox_belongs_to_agent_account
  validate :inbox_not_connected_elsewhere
  validate :inbox_without_active_agent_bot

  private

  def inbox_belongs_to_agent_account
    errors.add(:inbox, :invalid) unless inbox.account_id == ai_agent.account_id
  end

  def inbox_not_connected_elsewhere
    other = AiAgentInbox.where(inbox_id: inbox_id).where.not(id: id).first
    return if other.blank?

    errors.add(:base, I18n.t('ai_agents.inboxes.errors.already_connected', inbox: inbox.name, agent: other.ai_agent.name))
  end

  # An active Agent Bot takes precedence on the inbox, so the AI Agent would never reply there.
  def inbox_without_active_agent_bot
    errors.add(:base, I18n.t('ai_agents.inboxes.errors.agent_bot_connected', inbox: inbox.name)) if inbox.agent_bot_inbox&.active?
  end
end
