# Finds the knowledge chunks an AI Agent sends to the model for a conversation, up to its Context Limit (see
# AiAgent::KnowledgeChunk.searchable for the chunks compared). With an embedding model the search is hybrid: the nearest
# chunks by embedding and the chunks sharing the most words with the question are combined with Reciprocal Rank Fusion,
# so vector search finds what means the same and keywords find exact names and numbers. Without one only the words count.
# Chunks that are not relevant enough are left out of their list: those sharing no word with the question, and those
# farther than AI_AGENT_EMBEDDING_MAX_DISTANCE when it is set. No chunk at all means the model answers without knowledge.
# With a Context Expansion Radius the chunks next to the matches are sent too (see AiAgents::ContextExpansion).
#
# A follow-up question often leaves out its subject ("How much for 4?"), so a conversation with earlier customer turns
# is searched twice: with the latest turn, and with that turn joined to the ones before it. The first keeps a change of
# topic in the results, and the second counts less when the latest turn names its own subject (see
# NEW_TOPIC_QUERY_WEIGHTS). Agent replies stay out of the search, because they added noise.
class AiAgents::KnowledgeRetriever
  MAX_QUERY_CHARACTERS = 4_000
  CONTEXT_TURNS = 2
  MAX_CONTEXT_CHARACTERS = 1_000

  # Each list takes this many chunks, or the Context Limit when it is higher, and only the top context_limit chunks of the
  # fused ranking reach the model, so a lower limit sends less without changing the ranking. Smaller lists ranked some
  # answers lower in evals/ai-agent (#103).
  CANDIDATES = 40

  # Fusion settings, chosen with evals/ai-agent on lists of CANDIDATES: k evens out how much a top rank counts against a
  # lower one, keywords count half as much as embeddings because they match on any shared word, however common, and the
  # query with earlier turns counts most because a follow-up is hardly searchable on its own. When the vector and keyword
  # searches of the latest turn agree on their top chunk, that turn names its own subject, so the query with earlier turns
  # counts no more than it: at 4 the earlier topic outranked a new one, most of all in Q&A that ask the same questions
  # about many services (#141). A follow-up that leaves out its subject rarely gets the same top chunk from both searches.
  RRF_K = 20
  KEYWORD_WEIGHT = 0.5
  QUERY_WEIGHTS = [1.0, 4.0].freeze
  NEW_TOPIC_QUERY_WEIGHTS = [1.0, 1.0].freeze

  # rank starts at 1 and orders the chunks in the prompt. score is the RRF score: higher is closer, and it says nothing
  # about relevance on its own. A chunk sent as the neighbor of a match (see AiAgents::ContextExpansion) has no score, and
  # neighbor_of is the rank of that match.
  Hit = Data.define(:chunk, :rank, :score, :neighbor_of) do
    def initialize(chunk:, rank:, score:, neighbor_of: nil)
      super
    end
  end
  # queries: the latest customer turn, then that turn with the earlier ones when there are any.
  Result = Data.define(:mode, :embedding_model, :queries, :hits)

  # messages: { role: :user | :assistant, content: }, oldest first.
  pattr_initialize [:ai_agent!, :messages!]

  def perform
    embedding_model = AiAgents::LlmClient.embedding_model
    mode = embedding_model ? 'hybrid' : 'keyword'
    queries = search_queries
    Result.new(mode: mode, embedding_model: embedding_model, queries: queries, hits: hits(mode, embedding_model, queries))
  end

  private

  def search_queries
    *earlier, latest = customer_turns.last(CONTEXT_TURNS + 1)
    return [] if latest.blank?

    latest_query = latest.last(MAX_QUERY_CHARACTERS)
    return [latest_query] if earlier.empty?

    [latest_query, "#{earlier.join("\n").last(MAX_CONTEXT_CHARACTERS)}\n#{latest}".last(MAX_QUERY_CHARACTERS)]
  end

  # The messages between two replies are one turn, so a burst of short messages is searched as one question.
  def customer_turns
    messages.slice_when { |before, after| before[:role] != after[:role] }.select { |turn| turn.first[:role] == :user }
            .map { |turn| turn.pluck(:content).join("\n") }
  end

  # The request log gets the search after its embedding step, with the content of each chunk it found (see
  # AiAgents::RequestRecorder).
  def hits(mode, embedding_model, queries)
    chunks = ai_agent.knowledge_chunks.searchable(embedding_model)
    return [] if queries.empty? || !chunks.exists?

    vectors = embedding_model ? AiAgents::LlmClient.new.embed(queries, input_type: :query) : []
    AiAgents::RequestRecorder.step(:retrieval, { mode: mode, queries: queries }) do |step|
      ranked(chunks, queries, vectors).tap { |hits| step.output = { hits: hits.map { |hit| logged_hit(hit) } } }
    end
  end

  def ranked(chunks, queries, vectors)
    matches = fused(chunks, queries, vectors).first(ai_agent.context_limit)
    radius = ai_agent.context_expansion_radius
    return matches.map.with_index(1) { |(chunk, score), rank| Hit.new(chunk: chunk, rank: rank, score: score) } if radius.zero?

    AiAgents::ContextExpansion.new(chunks: chunks, matches: matches, radius: radius, limit: ai_agent.context_limit).perform
  end

  # distance is the cosine distance of a chunk the embedding search found, nil for the others.
  def logged_hit(hit)
    chunk = hit.chunk
    { rank: hit.rank, chunk_id: chunk.id, chunkable_type: chunk.chunkable_type, chunkable_id: chunk.chunkable_id, score: hit.score,
      distance: chunk.attributes['neighbor_distance'], neighbor_of: hit.neighbor_of, content: chunk.content }
  end

  # A chunk scores weight / (RRF_K + rank) for each list it is in, so one found by several searches ranks above one found
  # by a single search. The vector list goes first so that a chunk it found keeps its distance.
  def fused(chunks, queries, vectors)
    lists = queries.zip(vectors).map do |query, vector|
      [vector ? nearest_chunks(chunks, vector).to_a : [], keyword_matches(chunks, query)]
    end
    scores = Hash.new(0.0)
    lists.zip(query_weights(*lists.first)) do |(nearest, keyword), query_weight|
      [[nearest, 1.0], [keyword, KEYWORD_WEIGHT]].each do |list, list_weight|
        list.each.with_index(1) { |chunk, rank| scores[chunk] += query_weight * list_weight / (RRF_K + rank) }
      end
    end
    scores.sort_by { |chunk, score| [-score, chunk.id] }
  end

  # nearest and keyword are the lists of the latest turn.
  def query_weights(nearest, keyword)
    nearest.any? && nearest.first == keyword.first ? NEW_TOPIC_QUERY_WEIGHTS : QUERY_WEIGHTS
  end

  def nearest_chunks(chunks, vector)
    nearest = chunks.nearest_neighbors(:embedding, vector, distance: 'cosine').limit(candidates)
    max_distance = AiAgents::LlmClient.embedding_max_distance
    max_distance ? nearest.select { |chunk| chunk.neighbor_distance <= max_distance } : nearest
  end

  def keyword_matches(chunks, query)
    chunks.keyword_ranked(query).limit(candidates).select { |chunk| chunk.keyword_rank.positive? }
  end

  def candidates
    [CANDIDATES, ai_agent.context_limit].max
  end
end
