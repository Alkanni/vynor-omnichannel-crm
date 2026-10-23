# Packs paragraphs into chunks of at most CHUNK_SIZE characters; longer paragraphs are cut at whitespace.
class AiAgents::TextChunker
  CHUNK_SIZE = 1_500
  PIECE_PATTERN = /.{1,#{CHUNK_SIZE}}(?:\s+|\z)|.{#{CHUNK_SIZE}}/m

  def self.split(text)
    text.split(/\n{2,}/).map(&:strip).compact_blank.flat_map { |paragraph| pieces(paragraph) }.each_with_object([]) do |piece, chunks|
      if chunks.last && chunks.last.length + piece.length + 2 <= CHUNK_SIZE
        chunks.last << "\n\n" << piece
      else
        chunks << piece.dup
      end
    end
  end

  def self.pieces(paragraph)
    return [paragraph] if paragraph.length <= CHUNK_SIZE

    paragraph.scan(PIECE_PATTERN).map(&:strip).compact_blank
  end
  private_class_method :pieces
end
