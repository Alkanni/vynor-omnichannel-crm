# Talks to the OpenAI-compatible endpoint configured in Super Admin (CAPTAIN_OPEN_AI_API_KEY / CAPTAIN_OPEN_AI_ENDPOINT), such as
# OpenAI, 9router or OpenRouter. Embeddings may use their own endpoint and key (AI_AGENT_EMBEDDING_*); without an embedding model,
# knowledge is searched by keywords instead (see AiAgent::KnowledgeChunk.keyword_ranked).
class AiAgents::LlmClient
  EMBEDDING_DIMENSIONS = 1536

  class << self
    def configured? = api_key.present?
    def api_key = setting('CAPTAIN_OPEN_AI_API_KEY')
    def embedding_model = setting('AI_AGENT_EMBEDDING_MODEL')
    def embedding_api_key = setting('AI_AGENT_EMBEDDING_API_KEY') || api_key

    def setting(name)
      InstallationConfig.find_by(name: name)&.value.presence
    end
  end

  def embed(texts)
    with_context(self.class.embedding_api_key, self.class.setting('AI_AGENT_EMBEDDING_ENDPOINT') || endpoint) do |context|
      context.embed(texts, model: self.class.embedding_model, provider: :openai, assume_model_exists: true,
                           dimensions: EMBEDDING_DIMENSIONS).vectors
    end
  end

  # Gateways name models their own way (e.g. cx/gpt-5.5 on 9router), so the model ID is sent as is instead of being
  # looked up in the RubyLLM registry. The structured reply comes back as the arguments of a forced function call,
  # because some gateways drop response_format (9router with Codex models answers in plain text) while function calling
  # works on them. Returns the arguments as a Hash, or the text when the model answered without calling the function.
  def chat(model:, temperature:, instructions:, messages:, schema:)
    with_context(self.class.api_key, endpoint) do |context|
      tool = AiAgents::ReplyTool.new(**schema)
      chat = context.chat(model: model, provider: :openai, assume_model_exists: true)
                    .with_instructions(instructions).with_temperature(temperature).with_tool(tool, choice: tool.name)
      messages.each { |message| chat.add_message(message) }
      result = chat.complete
      result.is_a?(RubyLLM::Tool::Halt) ? result.content.deep_stringify_keys : result.content
    end
  end

  private

  def with_context(api_key, endpoint, &)
    raise AiAgents::LlmError, I18n.t('ai_agents.llm.errors.not_configured') if api_key.blank?

    Llm::Config.with_api_key(api_key, api_base: "#{endpoint.chomp('/')}/v1", &)
  # Provider messages can echo the endpoint or parts of the key, so only the error type reaches users;
  # the original error stays attached as the cause for exception tracking.
  rescue RubyLLM::Error, Faraday::Error => e
    raise AiAgents::LlmError, I18n.t('ai_agents.llm.errors.request_failed', reason: e.class.name.demodulize)
  end

  def endpoint
    self.class.setting('CAPTAIN_OPEN_AI_ENDPOINT') || LlmConstants::OPENAI_API_ENDPOINT
  end
end
