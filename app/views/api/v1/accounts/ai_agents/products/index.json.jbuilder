json.payload do
  json.array! @products do |product|
    json.partial! 'api/v1/models/ai_agent_product', formats: [:json], product: product
  end
end
