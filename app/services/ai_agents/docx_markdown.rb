# Turns the XML of a DOCX file into the Markdown AiAgents::TextChunker understands: paragraphs separated by a blank line,
# heading styles as headings, and tables as tables. Headings are recognized by their style name, because the style id
# depends on the language of Word ("Heading1", "Judul1"). styles is nil for a file without a styles part.
class AiAgents::DocxMarkdown
  NAMESPACE = { 'w' => 'http://schemas.openxmlformats.org/wordprocessingml/2006/main' }.freeze
  HEADING_STYLE_NAME = /\Aheading ([1-6])\z/i

  pattr_initialize :document, :styles

  def text
    blocks = document.xpath('//w:body//w:tbl[not(ancestor::w:tbl)] | //w:body//w:p[not(ancestor::w:tbl)]', NAMESPACE)
    blocks.map { |node| node.name == 'tbl' ? table(node) : paragraph(node) }.compact_blank.join("\n\n")
  end

  private

  def paragraph(node)
    content = node.xpath('.//w:t', NAMESPACE).map(&:text).join
    level = heading_levels[node.at_xpath('w:pPr/w:pStyle/@w:val', NAMESPACE)&.value]
    level && content.present? ? "#{'#' * level} #{content}" : content
  end

  def table(node)
    header, *rows = node.xpath('w:tr', NAMESPACE).map { |row| row.xpath('w:tc', NAMESPACE).map { |cell| cell_text(cell) } }
    return if header.nil?

    [header, header.map { '---' }, *rows].map { |cells| "| #{cells.join(' | ')} |" }.join("\n")
  end

  def cell_text(cell)
    cell.xpath('.//w:p', NAMESPACE).map { |line| line.xpath('.//w:t', NAMESPACE).map(&:text).join }.compact_blank.join(' ').gsub('|', '\|')
  end

  def heading_levels
    @heading_levels ||= (styles&.xpath('//w:style', NAMESPACE) || []).each_with_object({}) do |style, levels|
      level = style.at_xpath('w:name/@w:val', NAMESPACE)&.value.to_s[HEADING_STYLE_NAME, 1]
      levels[style['w:styleId']] = level.to_i if level
    end
  end
end
