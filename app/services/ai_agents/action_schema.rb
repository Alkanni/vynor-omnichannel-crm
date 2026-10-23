# The conversation actions an AI agent may take, as structured output fields next to its reply: "handoff" when
# Agent Transfer Conditions are set, "labels" (limited to the allowed labels) when labels are allowed, and a Google
# Sheets row ("write_sheet_row" + "sheet_row") when the agent's sheet integration is ready to write.
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

  # written_rows: the sheet rows (value lists) already written for the conversation, so they are not written again.
  pattr_initialize [:ai_agent!, :written_rows]

  def any?
    properties.any?
  end

  def json_schema(name, properties = {})
    properties = properties.merge(self.properties)
    { name: name, schema: { type: 'object', properties: properties, required: properties.keys.map(&:to_s), additionalProperties: false } }
  end

  def instructions
    [handoff_instructions, label_instructions, sheet_instructions].compact.join("\n\n").presence
  end

  # Labels outside the allowed list are dropped here, whatever the model returned. The sheet row follows the
  # sheet's header order, with blanks for empty header cells.
  def parse(content)
    { handoff: handoff? && content['handoff'] == true, labels: Array(content['labels']) & allowed_labels, sheet_row: sheet_row(content) }
  end

  private

  def properties
    @properties ||= {}.tap do |properties|
      properties[:handoff] = { type: 'boolean' } if handoff?
      properties[:labels] = { type: 'array', items: { type: 'string', enum: allowed_labels } } if allowed_labels.any?
      properties.merge!(sheet_properties) if sheet
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
end
