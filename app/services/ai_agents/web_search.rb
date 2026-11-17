# Searches the web for a query written for it, as agreed in docs/ai-agent-web-search-decisions.md, through the provider set in
# AI_AGENT_WEB_SEARCH_PROVIDER (see AiAgents::WebSearch::Provider). Only the query (and the optional domains) leaves the
# installation. perform never raises for the provider: every outcome is a Result whose status says where the results came
# from or why there are none, so a reply can always go on with the knowledge only.
#
# Spend and the cache are kept in Redis, because Rails.cache is not shared between the web and worker containers. Spend is
# counted per UTC month in micro-dollars, for all providers together, from what each search cost. No request is made once it
# reaches AI_AGENT_WEB_SEARCH_MONTHLY_BUDGET, or after the provider said in the same month that its credits are gone, so the
# budget paces usage within a provider's free credit. Concurrent searches can overshoot it a little.
class AiAgents::WebSearch
  PROVIDERS = { 'exa' => Exa.new, 'tavily' => Tavily.new, 'brave' => Brave.new, 'perplexity' => Perplexity.new }.freeze
  DEFAULT_PROVIDER = 'exa'.freeze
  MAX_QUERY_CHARACTERS = 200
  # Short enough that the playground's worst case stays within Rack::Timeout next to the model calls.
  OPEN_TIMEOUT = 1
  READ_TIMEOUT = 4
  DEFAULT_MONTHLY_BUDGET = 8
  CACHE_TTL = 6.hours
  # Monthly keys outlive their month a little, so the spend of the month just ended can still be read.
  MONTH_KEY_TTL = 40.days

  # A provider answer that means the request or the key is wrong. Its message never holds the key.
  class RequestError < StandardError; end

  # Exa returns up to about three times highlights.maxCharacters per result (measured in #108), and other providers return
  # whole passages, so the text of a result that a prompt gets is cut to this.
  MAX_TEXT_CHARACTERS = 800

  # rank starts at 1. published_at is a Date when the provider gives one, never guessed. highlights are the excerpts of the
  # page that the provider returned.
  Item = Data.define(:rank, :title, :url, :published_at, :highlights) do
    # The highlights as one text of at most MAX_TEXT_CHARACTERS, as a reply prompt gets them.
    def text = highlights.join(' ').squish.truncate(MAX_TEXT_CHARACTERS, separator: ' ')
  end
  # status is one of searched, cached, skipped_budget, failed_timeout, failed_rate_limit, failed_credits, failed_provider, or
  # failed_request. latency_ms is the provider request's, nil when none was made. cost_usd is what this search cost.
  Result = Data.define(:status, :results, :latency_ms, :cost_usd)

  class << self
    # Blank turns web search off for every agent.
    def configured? = api_key.present?
    def api_key = AiAgents::LlmClient.setting('AI_AGENT_WEB_SEARCH_API_KEY')
    # One of the keys of PROVIDERS.
    def provider_name = AiAgents::LlmClient.setting('AI_AGENT_WEB_SEARCH_PROVIDER') || DEFAULT_PROVIDER
    def monthly_budget = Float(AiAgents::LlmClient.setting('AI_AGENT_WEB_SEARCH_MONTHLY_BUDGET') || DEFAULT_MONTHLY_BUDGET)
  end

  # domains: optional list of domains to search only.
  pattr_initialize [:query!, :domains]

  # The request log gets the query, the domains, and each result with the text a prompt gets, ranked as the provider ranked it
  # (see AiAgents::RequestRecorder).
  def perform
    AiAgents::RequestRecorder.step(:web_search, { provider: provider_name, query: query, domains: domains }) do |step|
      result = fetch
      items = result.results.map { |item| item.to_h.except(:highlights).merge(text: item.text) }
      step.output = { status: result.status, results: items, latency_ms: result.latency_ms, cost_usd: result.cost_usd }
      result
    end
  end

  private

  # The cached results of the query, else those of a search, unless the budget is spent.
  def fetch
    return Result.new(status: 'skipped_budget', results: [], latency_ms: nil, cost_usd: 0) if budget_exhausted?

    cached = Redis::Alfred.get(cache_key)
    return Result.new(status: 'cached', results: items(JSON.parse(cached)), latency_ms: nil, cost_usd: 0) if cached

    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
    status, results, cost = search
    Result.new(status: status, results: items(results), latency_ms: Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond) - started_at,
               cost_usd: cost)
  end

  # Returns the status, the provider's results, and what the search cost in USD. There is no retry, also not on 429.
  def search
    response = connection.run_request(request.verb, request.url, request.body, nil)
    return [failure_status(response), [], 0] unless response.status == 200

    results = provider.results(response.body)
    cost = provider.cost(response.body)
    record_spend(cost)
    Redis::Alfred.setex(cache_key, results.to_json, CACHE_TTL)
    ['searched', results, cost]
  rescue Faraday::TimeoutError
    ['failed_timeout', [], 0]
  # Net::HTTP reports an open timeout as a failed connection.
  rescue Faraday::ConnectionFailed => e
    [e.wrapped_exception.is_a?(Net::OpenTimeout) ? 'failed_timeout' : 'failed_provider', [], 0]
  rescue Faraday::Error
    ['failed_provider', [], 0]
  end

  def failure_status(response)
    body = response.body.is_a?(Hash) ? response.body : {}
    if provider.credits_gone?(response.status, body)
      Redis::Alfred.set(credits_gone_key, 1, ex: MONTH_KEY_TTL)
      return 'failed_credits'
    end

    case response.status
    when 429 then 'failed_rate_limit'
    when 500.. then 'failed_provider'
    else
      ChatwootExceptionTracker.new(RequestError.new("Web search provider #{provider_name} rejected the request " \
                                                    "(HTTP #{response.status}, #{provider.error_tag(body) || 'no tag'})")).capture_exception
      'failed_request'
    end
  end

  def budget_exhausted?
    spend, credits_gone = Redis::Alfred.with do |conn|
      conn.mget(format(Redis::Alfred::AI_AGENT_WEB_SEARCH_SPEND, month: month), credits_gone_key)
    end
    credits_gone.present? || spend.to_i >= self.class.monthly_budget * 1_000_000
  end

  def record_spend(cost)
    key = format(Redis::Alfred::AI_AGENT_WEB_SEARCH_SPEND, month: month)
    Redis::Alfred.with do |conn|
      conn.multi do |transaction|
        transaction.incrby(key, (cost * 1_000_000).round)
        transaction.expire(key, MONTH_KEY_TTL)
      end
    end
  end

  def items(results)
    results.each.with_index(1).map do |result, rank|
      Item.new(rank: rank, title: result['title'], url: result['url'], published_at: result['published']&.then { |date| Date.parse(date) },
               highlights: result['snippets'])
    end
  end

  def connection
    Faraday.new(headers: provider.headers(self.class.api_key)) do |faraday|
      faraday.response :json
      faraday.options.open_timeout = OPEN_TIMEOUT
      faraday.options.read_timeout = READ_TIMEOUT
    end
  end

  # The cache key covers the provider and every request parameter, domains included.
  def cache_key
    @cache_key ||= format(Redis::Alfred::AI_AGENT_WEB_SEARCH_CACHE,
                          digest: Digest::SHA256.hexdigest("#{provider_name} #{request.url} #{request.body}"))
  end

  def credits_gone_key
    format(Redis::Alfred::AI_AGENT_WEB_SEARCH_CREDITS_GONE, provider: provider_name, month: month)
  end

  def request
    @request ||= provider.request(query, domains)
  end

  def provider
    @provider ||= PROVIDERS.fetch(provider_name)
  end

  def provider_name
    @provider_name ||= self.class.provider_name
  end

  def month
    @month ||= Time.now.utc.strftime('%Y-%m')
  end
end
