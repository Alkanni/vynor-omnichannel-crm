# Sends the chunks next to the matches of the knowledge search with them. A section longer than one chunk is often cut
# between a step and the next or between a rule and its exception, so the chunk that matched may not hold the whole answer.
# The chunks up to the agent's Context Expansion Radius before and after a match are added, from the same section of the
# same source (see AiAgents::TextChunker::Chunk) and the same embedding model. Q&A entries, products, and chunks made
# before chunks kept their section have no neighbors.
#
# The Context Limit stays the number of chunks sent, neighbors included, so a neighbor can take the place of a lower match.
# A neighbor at distance d from the match ranked r competes as if it ranked r + d * NEIGHBOR_STEP, behind the match of
# that rank. A neighbor that is a match itself is sent as a match.
#
# In the prompt, each run of consecutive chunks of a section goes together in document order, and the runs follow the
# rank of their best match, so the model reads each part of a document in one piece. Ranks number the chunks in that
# order.
class AiAgents::ContextExpansion
  # Chosen with evals/ai-agent (issue #134): step 0 pushed out the answer of control questions at Context Limits 3 and 5,
  # and with step 2 or more limit 3 sent no neighbor at all, because the matches kept every place.
  NEIGHBOR_STEP = 1
  SECTION_COLUMNS = %i[chunkable_type chunkable_id section].freeze
  Hit = AiAgents::KnowledgeRetriever::Hit

  # chunks: the chunks the search compared. matches: [chunk, score] of the search, best first, up to limit.
  pattr_initialize [:chunks!, :matches!, :radius!, :limit!]

  # The Hit of each chunk to send, in prompt order.
  def perform
    picked = candidates.sort.uniq(&:last).first(limit)
    ranks = prompt_order(picked.map(&:last)).each.with_index(1).to_h
    (match_hits(ranks) + neighbor_hits(picked, ranks)).sort_by(&:rank)
  end

  private

  def match_hits(ranks)
    matches.filter_map { |chunk, score| Hit.new(chunk: chunk, rank: ranks[chunk.id], score: score) if ranks.key?(chunk.id) }
  end

  # Each neighbor is the neighbor of the match it was picked for.
  def neighbor_hits(picked, ranks)
    neighbor_of = picked.to_h { |_place, _distance, from, _side, id| [id, ranks[matches[from - 1].first.id]] }.except(*match_ranks.keys)
    chunks.where(id: neighbor_of.keys).map { |chunk| Hit.new(chunk: chunk, rank: ranks[chunk.id], score: nil, neighbor_of: neighbor_of[chunk.id]) }
  end

  # The runs of consecutive chunks of a section, each in document order, ordered by their best match.
  def prompt_order(ids)
    runs(ids).sort_by { |run| run.filter_map { |id| match_ranks[id] }.min }.flatten
  end

  # [place, distance, rank of its match, side, chunk id] of each match and each neighbor; the lowest place goes first, and
  # at the same place a match goes before a neighbor, a nearer neighbor before a farther one, and the following chunk
  # before the preceding one.
  def candidates
    matches.each.with_index(1).flat_map do |(chunk, _score), rank|
      [[rank, 0, rank, 0, chunk.id], *neighbors(chunk).map { |distance, side, id| [rank + (distance * NEIGHBOR_STEP), distance, rank, side, id] }]
    end
  end

  # [distance, side, chunk id] of the chunks within the radius of a chunk in its section; side 0 follows it, 1 precedes it.
  def neighbors(chunk)
    ids = sections[section_key(chunk)]
    return [] unless ids

    position = ids.index(chunk.id)
    (1..radius).flat_map { |distance| [[distance, 0, position + distance], [distance, 1, position - distance]] }
               .filter_map { |distance, side, index| [distance, side, ids[index]] if index.between?(0, ids.size - 1) }
  end

  # The chunks picked as runs of consecutive chunks of one section in document order; any other chunk is a run of its own.
  def runs(ids)
    ids.sort_by { |id| positions[id] || [[], id] }.slice_when do |before, after|
      positions[before].nil? || positions[after].nil? || positions[before].first != positions[after].first ||
        positions[after].last != positions[before].last + 1
    end
  end

  # The chunk ids of each section that has a match, in document order, since the chunks of a record are created in it.
  def sections
    @sections ||= begin
      keys = matches.filter_map { |chunk, _score| section_key(chunk) }.uniq
      rows = keys.empty? ? [] : chunks.where(SECTION_COLUMNS => keys).order(:id).pluck(*SECTION_COLUMNS, :id)
      rows.group_by { |*key, _id| key }.transform_values { |section_rows| section_rows.map(&:last) }
    end
  end

  # [section key, position in the section] of each chunk of those sections.
  def positions
    @positions ||= sections.flat_map { |key, ids| ids.each_with_index.map { |id, index| [id, [key, index]] } }.to_h
  end

  # nil for a chunk without a section.
  def section_key(chunk)
    [chunk.chunkable_type, chunk.chunkable_id, chunk.section] if chunk.section
  end

  def match_ranks
    @match_ranks ||= matches.each.with_index(1).to_h { |(chunk, _score), rank| [chunk.id, rank] }
  end
end
