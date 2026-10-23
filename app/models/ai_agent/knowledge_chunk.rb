# == Schema Information
#
# Table name: ai_agent_knowledge_chunks
#
#  id                   :bigint           not null, primary key
#  chunkable_type       :string           not null
#  chunkable_updated_at :datetime         not null
#  content              :text             not null
#  embedding            :vector(1536)     not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  account_id           :bigint           not null
#  ai_agent_id          :bigint           not null
#  chunkable_id         :bigint           not null
#
# Indexes
#
#  index_ai_agent_knowledge_chunks_on_account_id   (account_id)
#  index_ai_agent_knowledge_chunks_on_ai_agent_id  (ai_agent_id)
#  index_ai_agent_knowledge_chunks_on_chunkable    (chunkable_type,chunkable_id)
#
class AiAgent::KnowledgeChunk < ApplicationRecord
  belongs_to :account
  belongs_to :ai_agent
  belongs_to :chunkable, polymorphic: true

  has_neighbors :embedding
end
