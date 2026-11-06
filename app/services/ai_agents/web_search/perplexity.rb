# Perplexity Search (https://docs.perplexity.ai/api-reference/search-post). It charges per request, whatever the number of
# results or the length of their text.
class AiAgents::WebSearch::Perplexity < AiAgents::WebSearch::Provider
  ENDPOINT = 'https://api.perplexity.ai/search'.freeze
  # A prompt gets at most AiAgents::WebSearch::MAX_TEXT_CHARACTERS of a result, about 200 tokens, so no more is fetched.
  REQUEST = { max_results: 3, max_tokens_per_page: 256, country: 'ID' }.freeze
  # US$5 per 1,000 requests (checked 2026-11-06).
  COST_USD = 0.005

  def request(query, domains)
    Request.new(verb: :post, url: ENDPOINT, body: { query: query, **REQUEST, search_domain_filter: domains.presence }.compact.to_json)
  end

  def results(body)
    body.fetch('results').map do |result|
      { 'title' => result['title'], 'url' => result['url'], 'published' => result['date'], 'snippets' => Array(result['snippet']) }
    end
  end

  def cost(_body) = COST_USD
end
