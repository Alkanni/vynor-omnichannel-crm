class AiAgents::ProcessKnowledgeSourceJob < ApplicationJob
  queue_as :low

  def perform(source)
    source.update!(status: :processing, error_message: nil)
    extracted = source.website? ? AiAgents::WebsiteContentExtractor.new(source.external_url).perform : { content: file_text(source) }
    raise AiAgents::ExtractionError, I18n.t('ai_agents.knowledge.errors.no_text') if extracted[:content].blank?

    source.store_extracted!(extracted[:content], title: extracted[:title]&.truncate(255) || source.title)
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
end
