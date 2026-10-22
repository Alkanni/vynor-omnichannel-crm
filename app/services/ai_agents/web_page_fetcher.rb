module AiAgents::WebPageFetcher
  HTML_CONTENT_TYPES = %w[text/html application/xhtml+xml].freeze
  XML_CONTENT_TYPES = %w[application/xml text/xml].freeze
  MAX_BYTES = 5.megabytes
  READ_TIMEOUT = 10

  module_function

  def html(url)
    fetch(url, HTML_CONTENT_TYPES)
  end

  def xml(url)
    fetch(url, XML_CONTENT_TYPES)
  end

  def fetch(url, content_types)
    SafeFetch.fetch(url, allowed_content_types: content_types, allowed_content_type_prefixes: [], max_bytes: MAX_BYTES,
                         read_timeout: READ_TIMEOUT) { |result| result.tempfile.read }
  rescue SafeFetch::InvalidUrlError, SafeFetch::UnsafeUrlError
    raise AiAgents::ExtractionError, I18n.t('ai_agents.knowledge.errors.unsafe_url')
  rescue SafeFetch::UnsupportedContentTypeError
    raise AiAgents::ExtractionError, I18n.t('ai_agents.knowledge.errors.not_a_web_page')
  rescue SafeFetch::FileTooLargeError
    raise AiAgents::ExtractionError, I18n.t('ai_agents.knowledge.errors.page_too_large')
  rescue SafeFetch::Error => e
    raise AiAgents::ExtractionError, I18n.t('ai_agents.knowledge.errors.fetch_failed', reason: e.message)
  end
end
