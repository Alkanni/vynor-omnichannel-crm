json.id promotion.id
json.ai_agent_id promotion.ai_agent_id
json.title promotion.title
json.description promotion.description
json.starts_on promotion.starts_on
json.ends_on promotion.ends_on
json.status promotion.status(current_date)
json.products promotion.products do |product|
  json.id product.id
  json.name product.name
end
json.created_at promotion.created_at.to_i
json.updated_at promotion.updated_at.to_i
