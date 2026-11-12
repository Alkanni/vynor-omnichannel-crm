# == Schema Information
#
# Table name: ai_agent_request_logs
#
#  id              :bigint           not null, primary key
#  error_class     :string
#  input           :jsonb            not null
#  latency_ms      :integer
#  output          :jsonb            not null
#  source          :string           not null
#  status          :string           not null
#  steps           :jsonb            not null
#  created_at      :datetime         not null
#  account_id      :bigint           not null
#  ai_agent_id     :bigint           not null
#  conversation_id :bigint
#  message_id      :bigint
#  reply_trace_id  :bigint
#
# Indexes
#
#  index_ai_agent_request_logs_on_ai_agent_id_and_created_at  (ai_agent_id,created_at)
#  index_ai_agent_request_logs_on_conversation_id             (conversation_id)
#  index_ai_agent_request_logs_on_created_at                  (created_at)
#
# What went into and came out of one run of an AI Agent, with each of its steps, while AI_AGENT_REQUEST_LOG_ENABLED is on
# (see AiAgents::RequestRecorder). Unlike AiAgent::ReplyTrace it keeps the content: the customer messages, the prompts, the
# model outputs, the knowledge chunks, and the web results, so only Super Admins may read it, and it is deleted after
# RETENTION (see AiAgents::RemoveOldRequestLogsJob).
# input is what the run started from: the messages of a reply, the Watcher, or the playground, or those of a Retrieval Test
# with its web query. output is what came of it: the bubbles a reply sent, its handoff and labels, the Watcher's actions, or
# a summary of a Retrieval Test or of indexing; it stays empty for a run that raised, and for a reply that was not sent
# because the customer wrote again. steps are in the order they ended, each one
# { step, started_ms (since the run started), latency_ms, input, output, model, tokens, error_class }.
# A reply and its Watcher run are linked to the trace of that reply; a reply that raised has no trace link, but its
# conversation and message.
class AiAgent::RequestLog < ApplicationRecord
  RETENTION = 30.days

  belongs_to :account
  belongs_to :ai_agent
  belongs_to :conversation, optional: true
  belongs_to :message, optional: true
  belongs_to :reply_trace, class_name: 'AiAgent::ReplyTrace', optional: true

  enum :source, %w[reply watcher playground retrieval_test indexing].index_by(&:itself)
  enum :status, %w[ok error].index_by(&:itself)

  # The runs without their steps, which hold the prompts, but with total_tokens: the input and output tokens of their model
  # calls, nil for a run without a model call that returned its tokens.
  scope :summaries, lambda {
    select(column_names - ['steps'], <<~SQL.squish)
      (SELECT SUM(COALESCE((entry #>> '{tokens,input}')::integer, 0) + COALESCE((entry #>> '{tokens,output}')::integer, 0))
              FILTER (WHERE entry -> 'tokens' <> 'null')
       FROM jsonb_array_elements(steps) entry) AS total_tokens
    SQL
  }

  # The latest message of the customer in the input of a reply, the Watcher, the playground, or a Retrieval Test.
  def last_customer_message
    input['messages']&.reverse_each&.find { |message| message['role'] == 'user' }&.dig('content')
  end
end
