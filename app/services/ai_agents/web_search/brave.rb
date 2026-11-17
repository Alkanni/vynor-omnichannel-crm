# Brave Search (https://api-dashboard.search.brave.com/app/documentation/web-search/query). Brave has no parameter for
# domains, so they go into the query as site: operators, and its titles and descriptions are HTML. It answers 429 both when
# too many searches are made and when the credits or the usage limit are used up, and tells them apart in error.code.
class AiAgents::WebSearch::Brave < AiAgents::WebSearch::Provider
  ENDPOINT = 'https://api.search.brave.com/res/v1/web/search'.freeze
  # search_lang has no Indonesian, so only the country is set.
  PARAMS = { count: 3, country: 'ID' }.freeze
  # The Search plan's price of US$5 per 1,000 requests (checked 2026-11-06).
  COST_USD = 0.005
  CREDITS_GONE_CODES = %w[QUOTA_LIMITED USAGE_LIMIT_EXCEEDED CREDIT_EXHAUSTED].freeze

  def request(query, domains)
    sites = domains.to_a.map { |domain| "site:#{domain}" }.join(' OR ')
    Request.new(verb: :get, url: "#{ENDPOINT}?#{{ q: [query, sites.presence].compact.join(' '), **PARAMS }.to_query}", body: nil)
  end

  def headers(api_key) = { 'X-Subscription-Token' => api_key, 'Accept' => 'application/json' }

  # Brave leaves web out of an answer that found nothing.
  def results(body)
    Array(body.dig('web', 'results')).map do |result|
      { 'title' => text(result['title']), 'url' => result['url'], 'published' => result['page_age'],
        'snippets' => [text(result['description'])].compact_blank }
    end
  end

  def cost(_body) = COST_USD

  def credits_gone?(status, body) = super || CREDITS_GONE_CODES.include?(body.dig('error', 'code'))

  def error_tag(body) = body.dig('error', 'code')

  private

  # Brave marks the query's words with <strong> and escapes characters such as ' as entities.
  def text(html) = Nokogiri::HTML5.fragment(html.to_s).text
end
