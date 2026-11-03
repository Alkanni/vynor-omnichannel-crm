# == Schema Information
#
# Table name: ai_agent_reply_traces
#
#  id                          :bigint           not null, primary key
#  blocked_reason              :string
#  cached_input_tokens         :integer
#  cited_ranks                 :jsonb            not null
#  embedding_model             :string
#  error_class                 :string
#  input_tokens                :integer
#  labels                      :jsonb            not null
#  latency_ms                  :integer
#  model                       :string           not null
#  output_tokens               :integer
#  reply_decision              :string
#  retrieval_mode              :string
#  retrieved                   :jsonb            not null
#  scope_decision              :string
#  scope_input_tokens          :integer
#  scope_latency_ms            :integer
#  scope_output_tokens         :integer
#  scope_policy_version        :integer          default(0), not null
#  status                      :integer          not null
#  watcher_cached_input_tokens :integer
#  watcher_input_tokens        :integer
#  watcher_output_tokens       :integer
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  account_id                  :bigint           not null
#  ai_agent_id                 :bigint           not null
#  conversation_id             :bigint           not null
#  message_id                  :bigint           not null
#
# Indexes
#
#  index_ai_agent_reply_traces_on_ai_agent_id_and_created_at  (ai_agent_id,created_at)
#  index_ai_agent_reply_traces_on_conversation_id             (conversation_id)
#
# What an AI Agent did for one customer message it answered (see AiAgents::ReplyJob), to explain and evaluate its replies:
# the decision of the scope check (see AiAgents::ScopeGuard) and how long it took, the knowledge chunks it retrieved, kept
# as references with their rank and score but never their content, the decision of a strict agent's reply, the ranks it
# cited, and why the reply was replaced with the knowledge gap message (see AiAgents::ReplyValidator), the model and the
# tokens of all its model calls, how long the reply took, and the outcome. Customer messages and replies are not copied
# here either.
# input_tokens, output_tokens, and cached_input_tokens add up the scope check and the reply model, of which the scope_*
# tokens are the scope check's share. The Watcher run after the reply (see AiAgents::WatchJob) adds its own watcher_*
# tokens. See AiAgents::LlmClient::Completion for cached input, and AiAgents::UsageReport for a summary of a period.
class AiAgent::ReplyTrace < ApplicationRecord
  belongs_to :account
  belongs_to :ai_agent
  belongs_to :conversation
  belongs_to :message

  # handoff: the reply handed the conversation over on the agent's transfer conditions. message_limit: the session had
  # reached the AI Message Limit, so no reply was generated. error: generating or sending the reply failed.
  enum :status, { replied: 0, handoff: 1, message_limit: 2, error: 3 }
end
