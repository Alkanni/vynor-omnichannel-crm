# == Schema Information
#
# Table name: bookings
#
#  id                  :bigint           not null, primary key
#  customer_name       :string           not null
#  details             :jsonb            not null
#  notes               :text
#  scheduled_at        :datetime         not null
#  service             :string           not null
#  status              :integer          default("requested"), not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  ai_agent_id         :bigint
#  contact_id          :bigint           not null
#  conversation_id     :bigint           not null
#  rescheduled_from_id :bigint
#
# Indexes
#
#  index_bookings_on_account_id_and_scheduled_at  (account_id,scheduled_at)
#  index_bookings_on_account_id_and_status        (account_id,status)
#  index_bookings_on_ai_agent_id                  (ai_agent_id)
#  index_bookings_on_contact_id                   (contact_id)
#  index_bookings_on_conversation_id              (conversation_id)
#  index_bookings_on_rescheduled_from_id          (rescheduled_from_id)
#
# A booking a customer asked for in a conversation. The AI agent records it as requested once the customer confirmed its
# summary (see AiAgents::ActionSchema and AiAgents::ConversationSession#apply!); staff confirm it. details holds the
# agent's own booking fields (AiAgent#booking_fields) as name => value. A booking the customer moved to another date,
# time, or service is rescheduled, and the booking that replaces it points to it (rescheduled_from).
class Booking < ApplicationRecord
  belongs_to :account
  belongs_to :conversation
  belongs_to :contact
  belongs_to :ai_agent, optional: true
  belongs_to :rescheduled_from, class_name: 'Booking', optional: true

  enum :status, { requested: 0, confirmed: 1, cancelled: 2, completed: 3, no_show: 4, rescheduled: 5 }
  # The statuses staff may move a booking to from each status: a cancelled or rescheduled booking stays as it is, completed
  # and no-show only correct each other, and none goes back to requested, which only a new booking has.
  NEXT_STATUSES = {
    'requested' => %w[confirmed cancelled completed no_show], 'confirmed' => %w[cancelled completed no_show],
    'completed' => %w[no_show], 'no_show' => %w[completed], 'cancelled' => [], 'rescheduled' => []
  }.freeze
  # What the staff may change on a booking besides its status, in the order an edit's activity names them (see #edit!).
  EDITABLE_FIELDS = %w[service customer_name scheduled_at notes details].freeze

  validates :service, :customer_name, presence: true, length: { maximum: 255 }
  validates :scheduled_at, presence: true
  validates :notes, length: { maximum: 5_000 }

  def next_statuses
    NEXT_STATUSES.fetch(status)
  end

  # A booking the staff recorded themselves (see Api::V1::Accounts::BookingsController#create), announced in its
  # conversation with who recorded it.
  def record_creation!(user)
    create_activity!(I18n.t('bookings.activity.created', user: user.name, id: id, service: service, scheduled_at: local_time(scheduled_at)))
  end

  # A staff change of the booking's fields, recorded in its conversation with who made it and each value before and after.
  # It changes neither the status nor tells the customer. Values it already has change nothing.
  def edit!(attributes, user)
    assign_attributes(attributes)
    changed = changes_to_save.slice(*EDITABLE_FIELDS)
    return if changed.empty?

    transaction do
      save!
      create_activity!(I18n.t('bookings.activity.edited', user: user.name, id: id, changes: describe_changes(changed)))
    end
  end

  # A staff change of the status, recorded in the booking's conversation with who made it. Setting the status it already
  # has changes nothing; the controller only lets through the status itself or one of #next_statuses. A status with a
  # message from the booking's agent (see AiAgent::BOOKING_MESSAGES) also tells the customer.
  def change_status!(new_status, user)
    return if status == new_status

    transaction do
      update!(status: new_status)
      create_activity!(I18n.t('bookings.activity.status_changed', user: user.name, id: id, status: I18n.t("bookings.statuses.#{new_status}")))
      send_status_message!
    end
  end

  private

  # The agent sends it, so a conversation the AI still handles stays with the AI (see Message#human_response?), and, as for
  # the agent's replies, it leaves waiting_since alone once a human handles the conversation. A channel whose reply window
  # has closed (see Conversation#can_reply?) gets no message, and the staff are told instead.
  def send_status_message!
    attribute = AiAgent::BOOKING_MESSAGES[status]
    template = ai_agent&.public_send(attribute) if attribute
    return if template.blank?

    status_label = I18n.t("bookings.statuses.#{status}")
    return create_activity!(I18n.t('bookings.activity.message_not_sent', id: id, status: status_label)) unless conversation.can_reply?

    conversation.messages.create!(
      account_id: account_id, inbox_id: conversation.inbox_id, message_type: :outgoing, sender: ai_agent,
      content: render_status_message(template), preserve_waiting_since: conversation.open?
    )
  end

  # The template has the variables of any message (see Liquidable) and the booking's (see BookingDrop). render! raises
  # instead of sending the customer a "Liquid error" text.
  def render_status_message(template)
    Liquid::Template.parse(template).render!(
      'booking' => BookingDrop.new(self), 'contact' => ContactDrop.new(conversation.contact), 'agent' => UserDrop.new(ai_agent),
      'conversation' => ConversationDrop.new(conversation), 'inbox' => InboxDrop.new(conversation.inbox), 'account' => AccountDrop.new(account)
    )
  end

  def describe_changes(changed)
    changed.map { |field, (from, to)| "#{self.class.human_attribute_name(field)}: #{describe_value(from)} → #{describe_value(to)}" }.join('; ')
  end

  def describe_value(value)
    case value
    when Time then local_time(value)
    when Hash then value.map { |name, text| "#{name} #{text.presence || '-'}" }.join(', ').presence || '-'
    else value.presence || '-'
    end
  end

  # In the time zone of the booking's agent, which the AI used to read the customer's time.
  def local_time(time)
    time.in_time_zone(ai_agent&.timezone || 'UTC').strftime('%Y-%m-%d %H:%M %Z')
  end

  def create_activity!(content)
    conversation.messages.create!(account_id: account_id, inbox_id: conversation.inbox_id, message_type: :activity, content: content)
  end
end
