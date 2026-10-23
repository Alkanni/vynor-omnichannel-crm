# The conversation actions an AI agent may take, as structured output fields next to its reply: "handoff" when
# Agent Transfer Conditions are set, and "labels" (limited to the allowed labels) when labels are allowed.
class AiAgents::ActionSchema
  HANDOFF_INSTRUCTIONS = <<~TEXT.freeze
    Set "handoff" to true when the conversation meets any of the transfer conditions below, and false otherwise.
    When it is true, use "messages" only for a short note that a human agent will continue the conversation.
  TEXT
  LABEL_INSTRUCTIONS = <<~TEXT.freeze
    Put in "labels" the labels that apply to the conversation, or leave it empty. Use only these labels: %<labels>s.
  TEXT

  pattr_initialize [:ai_agent!]

  def any?
    properties.any?
  end

  def json_schema(name, properties = {})
    properties = properties.merge(self.properties)
    { name: name, schema: { type: 'object', properties: properties, required: properties.keys.map(&:to_s), additionalProperties: false } }
  end

  def instructions
    [handoff_instructions, label_instructions].compact.join("\n\n").presence
  end

  # Labels outside the allowed list are dropped here, whatever the model returned.
  def parse(content)
    { handoff: handoff? && content['handoff'] == true, labels: Array(content['labels']) & allowed_labels }
  end

  private

  def properties
    @properties ||= {}.tap do |properties|
      properties[:handoff] = { type: 'boolean' } if handoff?
      properties[:labels] = { type: 'array', items: { type: 'string', enum: allowed_labels } } if allowed_labels.any?
    end
  end

  def handoff?
    ai_agent.transfer_conditions.present?
  end

  def allowed_labels
    @allowed_labels ||= ai_agent.account.labels.where(id: ai_agent.allowed_label_ids).order(:title).pluck(:title)
  end

  def handoff_instructions
    "#{HANDOFF_INSTRUCTIONS}Transfer conditions:\n#{ai_agent.transfer_conditions}" if handoff?
  end

  def label_instructions
    return if allowed_labels.empty?

    [format(LABEL_INSTRUCTIONS, labels: allowed_labels.join(', ')), ai_agent.label_conditions.presence].compact.join("Label rules:\n")
  end
end
