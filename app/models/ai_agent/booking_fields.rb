# An AI agent's own booking fields (AiAgent#booking_fields) and the services it offers (AiAgent#booking_services). Each
# field is an object with KEYS: its name, a description for the AI, its type (text, number, or choice), the options of a
# choice, and whether the AI needs it to record a booking. The AI fills the fields in its booking function (see
# AiAgents::ActionSchema) and staff in the booking form. The type and the options guide both, and a value outside them is
# kept as written; a required field holds back only the AI's bookings, which staff can complete. A field without a
# description, options, or requirement is a plain text, as every field was before fields had types.
class AiAgent::BookingFields
  KEYS = %w[name description type options required].freeze
  TYPES = %w[text number choice].freeze
  # A trimmed name of 1 to 50 characters on one line, for a field and for an option of a choice.
  NAME = /\A\S(?:.{0,48}\S)?\z/
  # A trimmed service name of 1 to 100 characters on one line.
  SERVICE = /\A\S(?:.{0,98}\S)?\z/
  MAX_DESCRIPTION = 200
  CHOICE_OPTIONS = 2..20
  # What the AI reads before the description of a field of the type.
  HINTS = { 'number' => 'Digits only.' }.freeze
  REQUIRED_INSTRUCTIONS = <<~TEXT.freeze
    The booking fields %<names>s are required: before the summary, ask the customer for each of them that the
    conversation does not give, and keep "create_booking" false while one of them is empty.
  TEXT

  # Whether values are strings of the pattern that are unique, case aside.
  def self.names?(values, pattern = NAME)
    values.is_a?(Array) && values.all? { |value| value.is_a?(String) && value.match?(pattern) } && values.map(&:downcase).uniq.size == values.size
  end

  # Whether fields is a list of field objects whose names are unique, case aside, and none of reserved.
  def self.valid?(fields, reserved)
    fields.is_a?(Array) && fields.all? { |field| field?(field) } && names?(fields.pluck('name')) &&
      !fields.pluck('name').map(&:downcase).intersect?(reserved)
  end

  def self.field?(field)
    return false unless field.is_a?(Hash) && field.keys.to_set == KEYS.to_set && TYPES.include?(field['type'])

    field['description'].is_a?(String) && field['description'].length <= MAX_DESCRIPTION && [true, false].include?(field['required']) &&
      options?(field)
  end

  # A choice has its own options, and a field of another type none.
  def self.options?(field)
    options = field['options']
    field['type'] == 'choice' ? names?(options) && CHOICE_OPTIONS.cover?(options.size) : options == []
  end
  private_class_method :field?, :options?

  pattr_initialize :ai_agent

  def names
    fields.pluck('name')
  end

  # The properties of the booking function that the agent's settings shape: "service" as one of its services, when it
  # lists them, and its own fields, each a text with its description and hints, or one of the options of a choice. As in
  # every booking field, an empty string is a value the conversation does not give.
  def properties
    properties = fields.to_h { |field| [field['name'], property(field)] }
    services.any? ? { 'service' => { type: 'string', enum: [*services, ''] } }.merge(properties) : properties
  end

  # What the AI is told about the required fields, nil when the agent has none.
  def instructions
    format(REQUIRED_INSTRUCTIONS, names: required.map { |name| %("#{name}") }.join(', ')) if required.any?
  end

  # The required fields that values (names with stripped values) leave empty.
  def missing(values)
    required.select { |name| values[name].blank? }
  end

  private

  def fields = ai_agent.booking_fields
  def services = ai_agent.booking_services

  def required
    fields.select { |field| field['required'] }.pluck('name')
  end

  def property(field)
    description = [('Required.' if field['required']), HINTS[field['type']], field['description'].presence].compact.join(' ')
    { type: 'string', enum: ([*field['options'], ''] if field['type'] == 'choice'), description: description.presence }.compact
  end
end
