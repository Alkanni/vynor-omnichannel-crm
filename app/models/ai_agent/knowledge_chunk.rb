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
#  section              :integer
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

  # How a knowledge source or product is indexed: its chunk count, the record version they were made from, when they were
  # made, and how many are not searchable because they were embedded with another model than the current one.
  IndexSummary = Data.define(:chunks, :version, :indexed_at, :other_model_chunks) do
    # 'outdated' once the record changed after its chunks were made, until the next indexing.
    def status_for(record) = version == record.updated_at ? 'indexed' : 'outdated'
  end

  # IndexSummary per chunkable_id for the chunks in scope.
  def self.index_summaries(embedding_model)
    other_model = embedding_model ? sanitize_sql_array(['COUNT(*) FILTER (WHERE embedding_model IS DISTINCT FROM ?)', embedding_model]) : '0'
    group(:chunkable_id).pluck(:chunkable_id, Arel.sql('COUNT(*)'), Arel.sql('MAX(chunkable_updated_at)'), Arel.sql('MAX(created_at)'),
                               Arel.sql(other_model)).to_h { |id, *summary| [id, IndexSummary.new(*summary)] }
  end

  # Text search configuration of keyword search. Its stemmer matches Indonesian word forms ("pemesanan" and "pesan").
  TEXT_SEARCH_CONFIG = 'indonesian'.freeze

  # Keyword search, on its own without an embedding model and next to vector search with one: chunks that share more words
  # with the query rank first. plainto_tsquery joins the query words with AND, so they are joined with OR instead to rank
  # partial matches too. Each chunk carries its rank as keyword_rank.
  KEYWORD_RANK = "ts_rank(to_tsvector('#{TEXT_SEARCH_CONFIG}', content), " \
                 "replace(plainto_tsquery('#{TEXT_SEARCH_CONFIG}', ?)::text, ' & ', ' | ')::tsquery)".freeze
  scope :keyword_ranked, lambda { |query|
    select(arel_table[Arel.star], sanitize_sql_array(["#{KEYWORD_RANK} AS keyword_rank", query])).order(Arel.sql('keyword_rank DESC, id'))
  }
end
