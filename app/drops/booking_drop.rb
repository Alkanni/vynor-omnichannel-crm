# A booking in the messages of its AI agent: the message it sends when the staff change its status (see
# Booking#change_status!) and the summary a reply shows the customer before they confirm it, when the booking is not
# recorded yet and has no id (see AiAgents::ReplyGenerator#booking_summary). The date and time are in the agent's time
# zone, and the date is numeric (22/11/2026) because the app loads no month names besides English
# (config.rails_i18n.enabled_modules).
class BookingDrop < BaseDrop
  def customer_name
    @obj.customer_name
  end

  def service
    @obj.service
  end

  def date
    local_scheduled_at.strftime('%d/%m/%Y')
  end

  def time
    local_scheduled_at.strftime('%H:%M')
  end

  def notes
    @obj.notes
  end

  # The agent's own fields as name => value, so a template can show one: {{ booking.details["Plat nomor"] }}.
  def details
    @obj.details
  end

  # The agent's own fields that have a value, one "name: value" line each, in the order of the agent's fields, since a
  # stored booking keeps them in jsonb's order.
  def extra_fields
    order = Array(@obj.ai_agent&.booking_fields).pluck('name')
    filled = @obj.details.select { |_name, value| value.present? }
    filled.sort_by { |name, _value| order.index(name) || order.size }.map { |name, value| "#{name}: #{value}" }.join("\n")
  end

  private

  def local_scheduled_at
    @obj.scheduled_at.in_time_zone(@obj.ai_agent.timezone)
  end
end
