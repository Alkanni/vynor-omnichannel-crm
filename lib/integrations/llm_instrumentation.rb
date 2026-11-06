# frozen_string_literal: true

require 'opentelemetry_config'

module Integrations::LlmInstrumentation
  include Integrations::LlmInstrumentationConstants
  include Integrations::LlmInstrumentationHelpers
  include Integrations::LlmInstrumentationSpans

  def instrument_llm_call(params)
    return yield unless ChatwootApp.otel_enabled?

    result = nil
    executed = false
    tracer.in_span(params[:span_name]) do |span|
      setup_span_attributes(span, params)
      result = yield
      executed = true
      record_completion(span, result)
      result
    end
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: resolve_account(params)).capture_exception
    executed ? result : yield
  end

  private

  def resolve_account(params)
    return params[:account] if params[:account].is_a?(Account)
    return Account.find_by(id: params[:account_id]) if params[:account_id].present?

    nil
  end
end
