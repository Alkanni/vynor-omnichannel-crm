# The conversation actions an AI agent may take, as structured output fields next to its reply: "handoff" when
# Agent Transfer Conditions are set, "labels" (limited to the allowed labels) when labels are allowed, and a Google
# Sheets row ("write_sheet_row" + "sheet_row") when the agent's sheet integration is ready to write, and a booking request
# ("create_booking" + "booking") when the agent records bookings (see AiAgent#booking?).
class AiAgents::ActionSchema
  HANDOFF_INSTRUCTIONS = <<~TEXT.freeze
    Set "handoff" to true when the conversation meets any of the transfer conditions below, and false otherwise.
    When it is true, use "messages" only for a short note that a human agent will continue the conversation.
  TEXT
  LABEL_INSTRUCTIONS = <<~TEXT.freeze
    Put in "labels" the labels that apply to the conversation, or leave it empty. Use only these labels: %<labels>s.
  TEXT
  SHEET_INSTRUCTIONS = <<~TEXT.freeze
    Set "write_sheet_row" to true when the conversation meets the condition below and its data is not in the rows already
    written, and false otherwise. When it is true, fill "sheet_row" with each column's value taken from the conversation,
    using an empty string when a value is unknown.
  TEXT
  BOOKING_INSTRUCTIONS = <<~TEXT.freeze
    Bookings: collect the values of the "booking" fields that the customer can give, then read them a short summary with
    the service, date, and time and ask them to confirm it. Do not ask for a phone number. In "messages", write a time the
    way the customer wrote it, such as "jam 2 siang", and a date as the calendar has it, and keep the summary and the
    confirmation to the booking, without prices or totals the customer did not ask for. Set "create_booking" to true only
    when the conversation meets the condition below and the customer has confirmed that summary, and false otherwise: a
    question about a service, its price, or the schedule is not a booking, and neither is a booking listed below or one
    the conversation already recorded. A change of the date, time, or service of an earlier booking needs its own summary
    and confirmation; once confirmed, it is a new booking, which the staff match with the earlier one. When it is true,
    fill "booking" from the conversation, with "date" as YYYY-MM-DD from the calendar, "time" as HH:MM (24-hour), "notes"
    for any special request, and an empty string for a value that is unknown, and tell the customer that the booking is a
    request that the staff will confirm. Before the summary, ask for the customer's name when the conversation does not
    give it.
  TEXT
  CALENDAR_DAYS = 14
  CALENDAR_NAMES = ['today', 'tomorrow', 'the day after tomorrow'].freeze
  BOOKING_TIME = /\A([01]?\d|2[0-3]):([0-5]\d)\z/

  # written_rows: the sheet rows (value lists) already written for the conversation, so they are not written again.
  # bookings: the bookings the customer still has in the conversation (see AiAgents::ConversationSession#bookings), so they
  # are not requested again.
  pattr_initialize [:ai_agent!, :written_rows, :bookings]

  def any?
    properties.any?
  end

  def json_schema(name, properties = {})
    properties = properties.merge(self.properties)
    { name: name, schema: { type: 'object', properties: properties, required: properties.keys.map(&:to_s), additionalProperties: false } }
  end

  def instructions
    [handoff_instructions, label_instructions, sheet_instructions, booking_instructions].compact.join("\n\n").presence
  end

  # Today and the next CALENDAR_DAYS days in the agent's time zone, for an agent that records bookings: the model turns
  # "besok" or "Jumat" into a date of it, and the reply check knows its numbers (see AiAgents::ReplyGenerator#current_time).
  def calendar
    return unless ai_agent.booking?

    today = Time.current.in_time_zone(ai_agent.timezone).to_date
    days = (0..CALENDAR_DAYS).map { |offset| [(today + offset).strftime('%A %Y-%m-%d'), CALENDAR_NAMES[offset]&.then { |name| "(#{name})" }] }
    "Calendar: #{days.map { |day| day.compact.join(' ') }.join(', ')}"
  end

  # What the reply check reads as known besides the conversation and the sources, for an agent that records bookings: the
  # calendar, and the time the reply fills in "booking", since its messages may restate that time in 24-hour form ("13.00"
  # for "jam 1 siang") whether or not the customer confirmed it yet.
  def known_text(content)
    return unless ai_agent.booking?

    values = content['booking']
    time = scheduled_at(values['date'].to_s.strip, values['time'].to_s.strip)&.strftime('%H:%M') if values.is_a?(Hash)
    [calendar, time].compact.join("\n")
  end

  # Labels outside the allowed list are dropped here, whatever the model returned. The sheet row follows the
  # sheet's header order, with blanks for empty header cells. A booking the model asked for is either the attributes of a
  # Booking or the reason it cannot be one (see #booking_request).
  def parse(content)
    { handoff: handoff? && content['handoff'] == true, labels: Array(content['labels']) & allowed_labels, sheet_row: sheet_row(content),
      **booking_request(content) }
  end

  private

  def properties
    @properties ||= {}.tap do |properties|
      properties[:handoff] = { type: 'boolean' } if handoff?
      properties[:labels] = { type: 'array', items: { type: 'string', enum: allowed_labels } } if allowed_labels.any?
      properties.merge!(sheet_properties) if sheet
      properties.merge!(booking_properties) if ai_agent.booking?
    end
  end

  def handoff?
    ai_agent.transfer_conditions.present?
  end

  def allowed_labels
    @allowed_labels ||= ai_agent.account.labels.where(id: ai_agent.allowed_label_ids).order(:title).pluck(:title)
  end

  def sheet
    return @sheet if defined?(@sheet)

    @sheet = ai_agent.google_sheets_integration&.then { |integration| integration if integration.writable? }
  end

  def sheet_columns
    sheet.settings['columns']
  end

  def sheet_properties
    columns = sheet_columns.compact_blank.uniq
    {
      write_sheet_row: { type: 'boolean' },
      sheet_row: { type: 'object', properties: columns.index_with { { type: 'string' } }, required: columns, additionalProperties: false }
    }
  end

  def sheet_row(content)
    return unless sheet && content['write_sheet_row'] == true

    values = sheet_values(content['sheet_row'])
    values if values&.any?(&:present?)
  end

  def sheet_values(row)
    sheet_columns.map { |column| column.present? ? row[column].to_s.strip : '' } if row.is_a?(Hash)
  end

  def booking_keys
    AiAgent::BOOKING_CORE_FIELDS + ai_agent.booking_fields
  end

  def booking_properties
    {
      create_booking: { type: 'boolean' },
      booking: { type: 'object', properties: booking_keys.index_with { { type: 'string' } }, required: booking_keys, additionalProperties: false }
    }
  end

  # The booking the model asked for, with a blank name when it gave none, since the conversation's contact fills that in
  # (see AiAgents::ConversationSession#request_booking!), or the reason it cannot be a booking: no date and time that
  # parse, or no service. Both are nil when the model asked for none.
  def booking_request(content)
    return { booking: nil, booking_rejection: nil } unless ai_agent.booking? && content['create_booking'] == true

    fields = content['booking'].is_a?(Hash) ? content['booking'] : {}
    values = booking_keys.index_with { |key| fields[key].to_s.strip }
    scheduled_at = scheduled_at(values['date'], values['time'])
    return { booking: nil, booking_rejection: :invalid_schedule } unless scheduled_at
    return { booking: nil, booking_rejection: :missing_service } if values['service'].empty?

    booking = { service: values['service'], customer_name: values['customer_name'], scheduled_at: scheduled_at,
                notes: values['notes'].presence, details: values.slice(*ai_agent.booking_fields) }
    { booking: booking, booking_rejection: nil }
  end

  def scheduled_at(date, time)
    hour, minute = BOOKING_TIME.match(time)&.captures&.map(&:to_i)
    return unless hour

    day = Date.strptime(date, '%Y-%m-%d')
    Time.find_zone!(ai_agent.timezone).local(day.year, day.month, day.day, hour, minute)
  rescue Date::Error
    nil
  end

  def handoff_instructions
    "#{HANDOFF_INSTRUCTIONS}Transfer conditions:\n#{ai_agent.transfer_conditions}" if handoff?
  end

  def label_instructions
    return if allowed_labels.empty?

    [format(LABEL_INSTRUCTIONS, labels: allowed_labels.join(', ')), ai_agent.label_conditions.presence].compact.join("Label rules:\n")
  end

  def sheet_instructions
    return unless sheet

    written = written_rows.to_a.map(&:to_json).join("\n").presence || 'none'
    "#{SHEET_INSTRUCTIONS}Condition:\n#{sheet.settings['when_to_write']}\nColumns: #{sheet_columns.compact_blank.uniq.join(', ')}\n" \
      "Rows already written:\n#{written}"
  end

  def booking_instructions
    return unless ai_agent.booking?

    listed = bookings.to_a.map do |booking|
      "#{booking.service}, #{booking.scheduled_at.in_time_zone(ai_agent.timezone).strftime('%Y-%m-%d %H:%M')}, #{booking.status}"
    end
    "#{BOOKING_INSTRUCTIONS}Condition:\n#{ai_agent.booking_conditions}\n" \
      "Bookings already in this conversation:\n#{listed.join("\n").presence || 'none'}"
  end
end
