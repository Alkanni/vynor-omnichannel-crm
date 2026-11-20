# A booking in the message its AI agent sends when the staff change its status (see Booking#change_status!), with the date
# and time in the agent's time zone. The date is numeric (22/11/2026) because the app loads no month names besides English
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

  private

  def local_scheduled_at
    @obj.scheduled_at.in_time_zone(@obj.ai_agent.timezone)
  end
end
