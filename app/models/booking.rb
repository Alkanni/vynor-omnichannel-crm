# == Schema Information
#
# Table name: bookings
#
#  id              :bigint           not null, primary key
#  customer_name   :string           not null
#  details         :jsonb            not null
#  notes           :text
#  scheduled_at    :datetime         not null
#  service         :string           not null
#  status          :integer          default("requested"), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  ai_agent_id     :bigint
#  contact_id      :bigint           not null
#  conversation_id :bigint           not null
#
# Indexes
#
#  index_bookings_on_account_id_and_scheduled_at  (account_id,scheduled_at)
#  index_bookings_on_account_id_and_status        (account_id,status)
#  index_bookings_on_ai_agent_id                  (ai_agent_id)
#  index_bookings_on_contact_id                   (contact_id)
#  index_bookings_on_conversation_id              (conversation_id)
#
# A booking a customer asked for in a conversation. The AI agent records it as requested once the customer confirmed its
# summary (see AiAgents::ActionSchema and AiAgents::ConversationSession#apply!); staff confirm it. details holds the
# agent's own booking fields (AiAgent#booking_fields) as name => value.
class Booking < ApplicationRecord
  belongs_to :account
  belongs_to :conversation
  belongs_to :contact
  belongs_to :ai_agent, optional: true

  enum :status, { requested: 0, confirmed: 1, cancelled: 2, completed: 3, no_show: 4 }

  validates :service, :customer_name, presence: true, length: { maximum: 255 }
  validates :scheduled_at, presence: true
  validates :notes, length: { maximum: 5_000 }
end
