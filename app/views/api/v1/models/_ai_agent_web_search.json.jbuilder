json.status web_search.status
json.latency_ms web_search.latency_ms
json.cost_usd web_search.cost_usd
json.results web_search.results do |result|
  json.rank result.rank
  json.title result.title
  json.url result.url
  json.published_at result.published_at
  json.highlights result.highlights
  json.text result.text
end
