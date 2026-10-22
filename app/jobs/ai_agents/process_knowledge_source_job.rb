class AiAgents::ProcessKnowledgeSourceJob < ApplicationJob
  queue_as :low

  def perform(source)
    source.update!(status: :processing, error_message: nil)
    extracted = source.website? ? AiAgents::WebsiteContentExtractor.new(source.external_url).perform : { content: file_text(source) }
    raise AiAgents::ExtractionError, I18n.t('ai_agents.knowledge.errors.no_text') if extracted[:content].blank?

    store_content(source, extracted)
  rescue AiAgents::ExtractionError => e
    source.update!(status: :failed, error_message: e.message)
  rescue StandardError => e
    source.update!(status: :failed, error_message: I18n.t('ai_agents.knowledge.errors.processing_failed'))
    ChatwootExceptionTracker.new(e, account: source.account).capture_exception
  end

  private

  def file_text(source)
    AiAgents::FileTextExtractor.new(source.file).perform
  end

  def store_content(source, extracted)
    content = extracted[:content]
    limit = AiAgent::KnowledgeSource::MAX_EXTRACTED_CHARACTERS
    source.update!(
      title: extracted[:title]&.truncate(255) || source.title,
      content: content.first(limit),
      status: :ready,
      metadata: source.metadata.merge('truncated' => content.length > limit)
    )
  end
end
