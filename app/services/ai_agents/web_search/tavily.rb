# Tavily (https://docs.tavily.com/documentation/api-reference/endpoint/search). A basic search costs 1 credit for up to 20
# results. Tavily answers 432 once the plan's credits are used up and 433 once the pay-as-you-go limit is reached.
class AiAgents::WebSearch::Tavily < AiAgents::WebSearch::Provider
  ENDPOINT = 'https://api.tavily.com/search'.freeze
  # country only applies to the general topic, which is the default one.
  REQUEST = { search_depth: 'basic', max_results: 3, country: 'indonesia', include_published_date: true }.freeze
  # 1 credit at the pay-as-you-go price (checked 2026-11-06). Monthly plans cost less per credit, so the budget stops early
  # rather than late.
  COST_USD = 0.008
  CREDITS_GONE_STATUSES = [402, 432, 433].freeze

  def request(query, domains)
    Request.new(verb: :post, url: ENDPOINT, body: { query: query, **REQUEST, include_domains: domains.presence }.compact.to_json)
  end

  def results(body)
    body.fetch('results').map do |result|
      { 'title' => result['title'], 'url' => result['url'], 'published' => result['published_date'], 'snippets' => Array(result['content']) }
    end
  end

  def cost(_body) = COST_USD

  def credits_gone?(status, _body) = CREDITS_GONE_STATUSES.include?(status)
end
