# == Schema Information
#
# Table name: ai_agent_reply_traces
#
#  id                   :bigint           not null, primary key
#  embedding_model      :string
#  error_class          :string
#  input_tokens         :integer
#  labels               :jsonb            not null
#  latency_ms           :integer
#  model                :string           not null
#  output_tokens        :integer
#  retrieval_mode       :string
#  retrieved            :jsonb            not null
#  scope_policy_version :integer          default(0), not null
#  status               :integer          not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  account_id           :bigint           not null
#  ai_agent_id          :bigint           not null
#  conversation_id      :bigint           not null
#  message_id           :bigint           not null
#
# Indexes
#
#  index_ai_agent_reply_traces_on_ai_agent_id_and_created_at  (ai_agent_id,created_at)
#  index_ai_agent_reply_traces_on_conversation_id             (conversation_id)
#
# What an AI Agent did for one customer message it answered (see AiAgents::ReplyJob), to explain and evaluate its replies:
# the knowledge chunks it retrieved, kept as references with their rank and score but never their content, the model and
# the tokens it reported, how long the reply took, and the outcome. Customer messages are not copied here either.
class AiAgent::ReplyTrace < ApplicationRecord
  belongs_to :account
  belongs_to :ai_agent
  belongs_to :conversation
  belongs_to :message

  # handoff: the reply handed the conversation over on the agent's transfer conditions. message_limit: the session had
  # reached the AI Message Limit, so no reply was generated. error: generating or sending the reply failed.
  enum :status, { replied: 0, handoff: 1, message_limit: 2, error: 3 }
end
