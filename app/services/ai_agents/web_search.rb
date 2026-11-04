# Searches the web through Exa (https://exa.ai) for a query written for it, as agreed in docs/ai-agent-web-search-decisions.md.
# Only the query (and the optional domains) leaves the installation. perform never raises for Exa: every outcome is a Result
# whose status says where the results came from or why there are none, so a reply can always go on with the knowledge only.
#
# Spend and the cache are kept in Redis, because Rails.cache is not shared between the web and worker containers. Spend is
# counted per UTC month in micro-dollars from Exa's costDollars.total. No request is made once it reaches
# AI_AGENT_WEB_SEARCH_MONTHLY_BUDGET, or after Exa answered 402 in the same month: the Exa account has no payment method,
# so Exa stops at its free credit anyway and the budget paces usage within it. Concurrent searches can overshoot it a little.
class AiAgents::WebSearch
  ENDPOINT = 'https://api.exa.ai/search'.freeze
  MAX_QUERY_CHARACTERS = 200
  # lite costs the same for up to 10 results, but every result costs prompt tokens.
  REQUEST = { type: 'lite', numResults: 3, userLocation: 'ID', contents: { highlights: { maxCharacters: 800 } } }.freeze
  # Short enough that the playground's worst case stays within Rack::Timeout next to the model calls.
  OPEN_TIMEOUT = 1
  READ_TIMEOUT = 4
  DEFAULT_MONTHLY_BUDGET = 8
  CACHE_TTL = 6.hours
  # Monthly keys outlive their month a little, so the spend of the month just ended can still be read.
  MONTH_KEY_TTL = 40.days

  # An Exa answer that means the request or the key is wrong. Its message never holds the key.
  class RequestError < StandardError; end

  # rank starts at 1. published_at is a Date when Exa gives one, never guessed.
  Item = Data.define(:rank, :title, :url, :published_at, :highlights)
  # status is one of searched, cached, skipped_budget, failed_timeout, failed_rate_limit, failed_credits, failed_provider, or
  # failed_request. latency_ms is the Exa request's, nil when none was made. cost_usd is what Exa charged for this search.
  Result = Data.define(:status, :results, :latency_ms, :cost_usd)

  class << self
    # Blank turns web search off for every agent.
    def configured? = api_key.present?
    def api_key = AiAgents::LlmClient.setting('AI_AGENT_EXA_API_KEY')
    def monthly_budget = Float(AiAgents::LlmClient.setting('AI_AGENT_WEB_SEARCH_MONTHLY_BUDGET') || DEFAULT_MONTHLY_BUDGET)
  end

  # domains: optional list of domains to search only, sent as includeDomains.
  pattr_initialize [:query!, :domains]

  def perform
    return Result.new(status: 'skipped_budget', results: [], latency_ms: nil, cost_usd: 0) if budget_exhausted?

    cached = Redis::Alfred.get(cache_key)
    return Result.new(status: 'cached', results: items(JSON.parse(cached)), latency_ms: nil, cost_usd: 0) if cached

    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
    status, results, cost = search
    Result.new(status: status, results: items(results), latency_ms: Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond) - started_at,
               cost_usd: cost)
  end

  private

  # Returns the status, Exa's results, and what Exa charged in USD. There is no retry, also not on 429.
  def search
    response = connection.post(ENDPOINT, request_body)
    return [failure_status(response), [], 0] unless response.status == 200

    results = response.body.fetch('results').map { |result| result.slice('title', 'url', 'publishedDate', 'highlights') }
    cost = response.body.dig('costDollars', 'total').to_f
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
    case response.status
    when 402
      Redis::Alfred.set(format(Redis::Alfred::AI_AGENT_WEB_SEARCH_CREDITS_GONE, month: month), 1, ex: MONTH_KEY_TTL)
      'failed_credits'
    when 429 then 'failed_rate_limit'
    when 500.. then 'failed_provider'
    else
      # Exa's error text could echo the key, so only its machine-readable tag is kept.
      tag = response.body['tag'] if response.body.is_a?(Hash)
      ChatwootExceptionTracker.new(RequestError.new("Exa rejected the web search request (HTTP #{response.status}, #{tag || 'no tag'})"))
                              .capture_exception
      'failed_request'
    end
  end

  def budget_exhausted?
    spend, credits_gone = Redis::Alfred.with do |conn|
      conn.mget(format(Redis::Alfred::AI_AGENT_WEB_SEARCH_SPEND, month: month), format(Redis::Alfred::AI_AGENT_WEB_SEARCH_CREDITS_GONE, month: month))
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
      Item.new(rank: rank, title: result['title'], url: result['url'], published_at: result['publishedDate']&.then { |date| Date.parse(date) },
               highlights: Array(result['highlights']))
    end
  end

  def connection
    Faraday.new(headers: { 'x-api-key' => self.class.api_key, 'Content-Type' => 'application/json' }) do |faraday|
      faraday.response :json
      faraday.options.open_timeout = OPEN_TIMEOUT
      faraday.options.read_timeout = READ_TIMEOUT
    end
  end

  # The cache key covers every request parameter, domains included.
  def cache_key
    @cache_key ||= format(Redis::Alfred::AI_AGENT_WEB_SEARCH_CACHE, digest: Digest::SHA256.hexdigest(request_body))
  end

  def request_body
    @request_body ||= { query: query, **REQUEST, includeDomains: domains.presence }.compact.to_json
  end

  def month
    @month ||= Time.now.utc.strftime('%Y-%m')
  end
end
