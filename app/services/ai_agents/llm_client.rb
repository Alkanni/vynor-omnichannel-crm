# Talks to the OpenAI-compatible provider configured in Super Admin (CAPTAIN_OPEN_AI_API_KEY / CAPTAIN_OPEN_AI_ENDPOINT).
class AiAgents::LlmClient
  EMBEDDING_MODEL = LlmConstants::DEFAULT_EMBEDDING_MODEL

  def self.configured?
    api_key.present?
  end

  def self.api_key
    InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY')&.value
  end

  def embed(texts)
    with_context { |context| context.embed(texts, model: EMBEDDING_MODEL).vectors }
  end

  def chat(model:, temperature:, instructions:, messages:, schema:)
    with_context do |context|
      chat = context.chat(model: model).with_instructions(instructions).with_temperature(temperature).with_schema(schema)
      messages.each { |message| chat.add_message(message) }
      chat.complete.content
    end
  end

  private

  def with_context(&)
    api_key = self.class.api_key
    raise AiAgents::LlmError, I18n.t('ai_agents.llm.errors.not_configured') if api_key.blank?

    Llm::Config.with_api_key(api_key, api_base: api_base, &)
  rescue RubyLLM::Error, Faraday::Error => e
    raise AiAgents::LlmError, I18n.t('ai_agents.llm.errors.request_failed', reason: e.message)
  end

  def api_base
    endpoint = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')&.value.presence || LlmConstants::OPENAI_API_ENDPOINT
    "#{endpoint.chomp('/')}/v1"
  end
end
