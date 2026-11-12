# Talks to the OpenAI-compatible endpoint configured in Super Admin (CAPTAIN_OPEN_AI_API_KEY / CAPTAIN_OPEN_AI_ENDPOINT), such as
# OpenAI, 9router or OpenRouter. Embeddings may use their own endpoint and key (AI_AGENT_EMBEDDING_*); without an embedding model,
# knowledge is searched by keywords instead (see AiAgent::KnowledgeChunk.keyword_ranked).
class AiAgents::LlmClient
  # Retrieval models such as NVIDIA nemotron-3-embed-1b rank poorly unless queries and passages are told apart, and
  # gateways like 9router drop the input_type parameter, so the role goes into the text the way E5-style models expect.
  EMBEDDING_PREFIXES = { query: 'query: ', passage: 'passage: ' }.freeze
  # Token counts are nil when the gateway does not report usage. input_tokens leaves out cached_input_tokens, the input
  # the provider read from its prompt cache, as RubyLLM reports them apart; together they are the whole prompt. latency_ms
  # is how long the model took to answer.
  Completion = Data.define(:content, :input_tokens, :output_tokens, :cached_input_tokens, :latency_ms) do
    # The arguments of the function, empty when the model wrote text instead of calling it.
    def arguments = content.is_a?(Hash) ? content : {}
  end

  class << self
    def configured? = api_key.present?
    def api_key = setting('CAPTAIN_OPEN_AI_API_KEY')
    def embedding_model = setting('AI_AGENT_EMBEDDING_MODEL')
    def embedding_api_key = setting('AI_AGENT_EMBEDDING_API_KEY') || api_key
    # Cosine distance above which the embedding search leaves knowledge chunks out (see AiAgents::KnowledgeRetriever); nil keeps them all.
    def embedding_max_distance = setting('AI_AGENT_EMBEDDING_MAX_DISTANCE')&.then { |value| Float(value) }

    def setting(name)
      InstallationConfig.find_by(name: name)&.value.presence
    end
  end

  # input_type is :query for a customer question and :passage for knowledge. Vectors keep the model's own size
  # (e.g. 1536 for text-embedding-3-small, 2048 for NVIDIA nemotron-3-embed-1b). The request log gets the texts as sent, but
  # not the vectors (see AiAgents::RequestRecorder).
  def embed(texts, input_type:)
    inputs = texts.map { |text| "#{EMBEDDING_PREFIXES.fetch(input_type)}#{text}" }
    model = self.class.embedding_model
    AiAgents::RequestRecorder.step(:embedding, { input_type: input_type, texts: inputs }, model: model) do |step|
      vectors = with_context(self.class.embedding_api_key, self.class.setting('AI_AGENT_EMBEDDING_ENDPOINT') || endpoint) do |context|
        context.embed(inputs, model: model, provider: :openai, assume_model_exists: true).vectors
      end
      step.output = { vectors: vectors.size, dimensions: vectors.first&.size }
      vectors
    end
  end

  # Gateways name models their own way (e.g. cx/gpt-5.5 on 9router), so the model ID is sent as is instead of being
  # looked up in the RubyLLM registry. The structured reply comes back as the arguments of a forced function call,
  # because some gateways drop response_format (9router with Codex models answers in plain text) while function calling
  # works on them. The completion's content is the arguments as a Hash, or the text when the model answered without
  # calling the function. step names the call in the request log (see AiAgents::RequestRecorder).
  def chat(model:, temperature:, instructions:, messages:, schema:, step:) # rubocop:disable Metrics/ParameterLists
    input = { temperature: temperature, instructions: instructions, messages: messages, schema: schema[:name] }
    AiAgents::RequestRecorder.step(step, input, model: model) do |recorded|
      completion = with_context(self.class.api_key, endpoint) do |context|
        tool = AiAgents::ReplyTool.new(**schema)
        chat = context.chat(model: model, provider: :openai, assume_model_exists: true)
                      .with_instructions(instructions).with_temperature(temperature).with_tool(tool, choice: tool.name)
        messages.each { |message| chat.add_message(message) }
        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
        completion(chat, chat.complete, started_at)
      end
      recorded.output = completion.content
      recorded.tokens = { input: completion.input_tokens, output: completion.output_tokens, cached_input: completion.cached_input_tokens }
      completion
    end
  end

  private

  def completion(chat, result, started_at)
    # The model's response is the latest assistant message, also when the function call halted the chat.
    response = chat.messages.reverse.find { |message| message.role == :assistant }
    Completion.new(content: result.is_a?(RubyLLM::Tool::Halt) ? result.content.deep_stringify_keys : result.content,
                   input_tokens: response.input_tokens, output_tokens: response.output_tokens, cached_input_tokens: response.cached_tokens,
                   latency_ms: Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond) - started_at)
  end

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
