class AiAgents::FileTextExtractor
  DOCX_DOCUMENT_ENTRY = 'word/document.xml'.freeze
  DOCX_STYLES_ENTRY = 'word/styles.xml'.freeze
  MAX_DOCX_XML_SIZE = 50.megabytes
  MAX_PDF_PAGES = 2_000
  # UTF-8 uses at most 4 bytes per character, so this is enough bytes for the character limit.
  MAX_PLAIN_TEXT_BYTES = AiAgent::KnowledgeSource::MAX_EXTRACTED_CHARACTERS * 4

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

  # Pages are read one at a time and reading stops once enough text is collected, so huge PDFs
  # do not load every page into memory.
  def pdf_text(path)
    reader = PDF::Reader.new(path)
    text = +''
    1.upto([reader.page_count, MAX_PDF_PAGES].min) do |number|
      break if text.length > AiAgent::KnowledgeSource::MAX_EXTRACTED_CHARACTERS

      text << reader.page(number).text << "\n\n"
    end
    text
  rescue PDF::Reader::MalformedPDFError, PDF::Reader::UnsupportedFeatureError, PDF::Reader::EncryptedPDFError
    raise AiAgents::ExtractionError, I18n.t('ai_agents.knowledge.errors.unreadable_file')
  end

  def docx_text(path)
    Zip::File.open(path) do |zip|
      document = docx_xml(zip, DOCX_DOCUMENT_ENTRY)
      raise AiAgents::ExtractionError, I18n.t('ai_agents.knowledge.errors.unreadable_file') if document.nil?

      AiAgents::DocxMarkdown.new(document, docx_xml(zip, DOCX_STYLES_ENTRY)).text
    end
  rescue Zip::Error
    raise AiAgents::ExtractionError, I18n.t('ai_agents.knowledge.errors.unreadable_file')
  end

  def docx_xml(zip, name)
    entry = zip.find_entry(name)
    return if entry.nil?
    raise AiAgents::ExtractionError, I18n.t('ai_agents.knowledge.errors.unreadable_file') if entry.size > MAX_DOCX_XML_SIZE

    Nokogiri::XML(entry.get_input_stream.read)
  end

  def doc_text(path)
    output, status = Open3.capture2('antiword', '-w', '0', path)
    raise AiAgents::ExtractionError, I18n.t('ai_agents.knowledge.errors.unreadable_file') unless status.success?

    output
  end

  def plain_text(file)
    file.read(MAX_PLAIN_TEXT_BYTES).to_s.force_encoding(Encoding::UTF_8).scrub('').delete_prefix("\uFEFF")
  end
end
