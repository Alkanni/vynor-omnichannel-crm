# Exa (https://exa.ai/docs/reference/search), as agreed in docs/ai-agent-web-search-decisions.md. Exa states what a search
# cost in costDollars.total, and answers 402 once the account's credits are gone.
class AiAgents::WebSearch::Exa < AiAgents::WebSearch::Provider
  ENDPOINT = 'https://api.exa.ai/search'.freeze
  # lite costs the same for up to 10 results, but every result costs prompt tokens.
  REQUEST = { type: 'lite', numResults: 3, userLocation: 'ID', contents: { highlights: { maxCharacters: 800 } } }.freeze

  def request(query, domains)
    Request.new(verb: :post, url: ENDPOINT, body: { query: query, **REQUEST, includeDomains: domains.presence }.compact.to_json)
  end

  def headers(api_key) = { 'x-api-key' => api_key, 'Content-Type' => 'application/json' }

  def results(body)
    body.fetch('results').map do |result|
      { 'title' => result['title'], 'url' => result['url'], 'published' => result['publishedDate'], 'snippets' => Array(result['highlights']) }
    end
  end

  def cost(body) = body.dig('costDollars', 'total').to_f

  def error_tag(body) = body['tag']
end
