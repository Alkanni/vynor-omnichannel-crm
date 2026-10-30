# == Schema Information
#
# Table name: ai_agent_knowledge_chunks
#
#  id                   :bigint           not null, primary key
#  chunkable_type       :string           not null
#  chunkable_updated_at :datetime         not null
#  content              :text             not null
#  embedding            :vector
#  embedding_model      :string
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

  # The chunks knowledge search compares for an embedding model: only chunks embedded with it, since vectors of another
  # model differ in meaning and often in size (they count again once the agent is trained with it). Without an embedding
  # model every chunk is searched by keywords.
  scope :searchable, ->(embedding_model) { embedding_model ? where(embedding_model: embedding_model) : all }

  # Keyword search for installations without an embedding model: chunks that share more words with the query rank first.
  # plainto_tsquery joins the query words with AND, so they are joined with OR instead to rank partial matches too.
  # Each chunk carries its rank as keyword_rank.
  KEYWORD_RANK = "ts_rank(to_tsvector('simple', content), replace(plainto_tsquery('simple', ?)::text, ' & ', ' | ')::tsquery)".freeze
  scope :keyword_ranked, lambda { |query|
    select(arel_table[Arel.star], sanitize_sql_array(["#{KEYWORD_RANK} AS keyword_rank", query])).order(Arel.sql('keyword_rank DESC, id'))
  }
end
