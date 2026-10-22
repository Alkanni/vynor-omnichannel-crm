class AiAgents::FileTextExtractor
  DOCX_DOCUMENT_ENTRY = 'word/document.xml'.freeze
  DOCX_NAMESPACE = { 'w' => 'http://schemas.openxmlformats.org/wordprocessingml/2006/main' }.freeze
  MAX_DOCX_XML_SIZE = 50.megabytes

  def initialize(attachment)
    @attachment = attachment
  end

  def perform
    @attachment.open { |file| extract(file) }
  end

  private

  def extract(file)
    case File.extname(@attachment.filename.to_s).downcase
    when '.pdf' then pdf_text(file.path)
    when '.docx' then docx_text(file.path)
    when '.doc' then doc_text(file.path)
    else plain_text(file)
    end
  end

  def pdf_text(path)
    PDF::Reader.new(path).pages.map(&:text).join("\n\n")
  rescue PDF::Reader::MalformedPDFError, PDF::Reader::UnsupportedFeatureError, PDF::Reader::EncryptedPDFError
    raise AiAgents::ExtractionError, I18n.t('ai_agents.knowledge.errors.unreadable_file')
  end

  def docx_text(path)
    Zip::File.open(path) do |zip|
      entry = zip.find_entry(DOCX_DOCUMENT_ENTRY)
      raise AiAgents::ExtractionError, I18n.t('ai_agents.knowledge.errors.unreadable_file') if entry.nil? || entry.size > MAX_DOCX_XML_SIZE

      document = Nokogiri::XML(entry.get_input_stream.read)
      document.xpath('//w:body//w:p', DOCX_NAMESPACE).map { |paragraph| paragraph.xpath('.//w:t', DOCX_NAMESPACE).map(&:text).join }.join("\n")
    end
  rescue Zip::Error
    raise AiAgents::ExtractionError, I18n.t('ai_agents.knowledge.errors.unreadable_file')
  end

  def doc_text(path)
    output, status = Open3.capture2('antiword', '-w', '0', path)
    raise AiAgents::ExtractionError, I18n.t('ai_agents.knowledge.errors.unreadable_file') unless status.success?

    output
  end

  def plain_text(file)
    file.read.force_encoding(Encoding::UTF_8).scrub('').delete_prefix("\uFEFF")
  end
end
