# Splits Markdown-style text into chunks of at most CHUNK_SIZE characters that make sense on their own. A heading starts a
# new chunk and every chunk opens with its heading path, because text under a heading often does not repeat what the
# heading says. A table too long for one chunk is split between rows with its header repeated. The paragraphs of a section
# are packed together, and anything longer is cut at whitespace.
class AiAgents::TextChunker
  CHUNK_SIZE = 1_500
  MAX_HEADING_PATH = 200
  HEADING_PATTERN = /\A(\#{1,6})[ \t]+(.+?)[ \t]*\#*\z/
  TABLE_DELIMITER_PATTERN = /\A\|[\s:|-]*-[\s:|-]*\z/

  def self.split(text)
    sections(text).flat_map { |path, lines| section_chunks(path, lines) }
  end

  # [heading path, lines] of each stretch of text between headings; the text before the first heading has no path.
  def self.sections(text)
    headings = []
    [*text.lines(chomp: true).slice_before(HEADING_PATTERN), nil].each_cons(2).filter_map do |lines, following|
      marks, title = lines.first.match(HEADING_PATTERN)&.captures
      next ['', lines] unless marks

      headings = headings.select { |level, _title| level < marks.length } << [marks.length, title]
      section(headings.map(&:last).join(' > '), lines.drop(1), following && following.first[HEADING_PATTERN, 1].length > marks.length)
    end
  end

  # Heading text has to reach a chunk too. A heading with nothing under it becomes the text of its section, unless the deeper
  # heading after it carries it in its path, and a path too long to repeat on every chunk is kept in full once.
  def self.section(path, body, parent)
    return (parent ? nil : ['', [path]]) if body.all?(&:blank?)
    return [path, body] if path.length <= MAX_HEADING_PATH

    [path.truncate(MAX_HEADING_PATH), [path, '', *body]]
  end

  def self.section_chunks(path, lines)
    prefix = path.empty? ? '' : "#{path}\n\n"
    limit = CHUNK_SIZE - prefix.length
    blocks = lines.join("\n").split(/\n{2,}/).map(&:strip).compact_blank
    pack(blocks.flat_map { |block| pieces(block, limit) }, limit, "\n\n").map { |chunk| "#{prefix}#{chunk}" }
  end

  def self.pack(pieces, limit, separator)
    pieces.each_with_object([]) do |piece, packed|
      if packed.last && packed.last.length + separator.length + piece.length <= limit
        packed.last << separator << piece
      else
        packed << piece.dup
      end
    end
  end

  def self.pieces(block, limit)
    return [block] if block.length <= limit

    table?(block) ? table_pieces(block, limit) : cut(block, limit)
  end

  def self.table?(block)
    first_line, second_line = block.split("\n", 3)
    first_line.start_with?('|') && second_line.to_s.match?(TABLE_DELIMITER_PATTERN)
  end

  # A header taking up most of a chunk leaves too little room for rows, so such a table is cut like plain text.
  def self.table_pieces(block, limit)
    header, delimiter, *rows = block.split("\n")
    head = "#{header}\n#{delimiter}"
    room = limit - head.length - 1
    return cut(block, limit) if room < limit / 2

    pack(rows.flat_map { |row| row.length > room ? cut(row, room) : [row] }, room, "\n").map { |group| "#{head}\n#{group}" }
  end

  def self.cut(text, limit)
    text.scan(/.{1,#{limit}}(?:\s+|\z)|.{#{limit}}/m).map(&:strip).compact_blank
  end

  private_class_method :sections, :section, :section_chunks, :pack, :pieces, :table?, :table_pieces, :cut
end
