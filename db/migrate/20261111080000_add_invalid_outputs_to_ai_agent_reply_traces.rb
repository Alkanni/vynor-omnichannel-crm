class AddInvalidOutputsToAiAgentReplyTraces < ActiveRecord::Migration[7.1]
  # A strict agent asks its reply model once more when an output has no valid decision (#142), and the trace keeps the shape
  # of each such output, without its content, so their cause can be studied. Older rows read as having none. Rolling back
  # drops the column.
  def change
    add_column :ai_agent_reply_traces, :invalid_outputs, :jsonb, null: false, default: []
  end
end
