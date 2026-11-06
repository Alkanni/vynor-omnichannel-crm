# A web search API that AiAgents::WebSearch can search with. A provider answers four questions: the request for a query
# (request), the results of a 200 answer (results), what that search cost in USD (cost), and whether an answer means the
# account ran out of credits (credits_gone?). AiAgents::WebSearch keeps the budget, the cache, the timeouts, and the
# statuses the same for every provider. To add one, subclass this, list an instance in AiAgents::WebSearch::PROVIDERS,
# and add it to the options of AI_AGENT_WEB_SEARCH_PROVIDER in config/installation_config.yml.
#
# results gives each result as a hash with the string keys title, url, published (a date string, nil when the provider
# gives none), and snippets (the excerpts of the page that match the query).
class AiAgents::WebSearch::Provider
  # body is nil for a GET, whose parameters are in url.
  Request = Data.define(:verb, :url, :body)

  def headers(api_key) = { 'Authorization' => "Bearer #{api_key}", 'Content-Type' => 'application/json' }

  # body is the parsed answer, or {} when it was not JSON.
  def credits_gone?(status, _body) = status == 402

  # A machine-readable code from a rejected answer, never its message, which could echo the key.
  def error_tag(_body) = nil
end
