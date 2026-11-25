json.payload do
  json.array! @promotions do |promotion|
    json.partial! 'api/v1/models/ai_agent_promotion', formats: [:json], promotion: promotion, current_date: @current_date
  end
end
