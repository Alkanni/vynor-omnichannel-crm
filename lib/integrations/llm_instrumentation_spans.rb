# frozen_string_literal: true

require 'opentelemetry_config'

module Integrations::LlmInstrumentationSpans
  include Integrations::LlmInstrumentationConstants

  def tracer
    @tracer ||= OpentelemetryConfig.tracer
  end

  def start_llm_turn_span(params)
    return unless ChatwootApp.otel_enabled?

    span = tracer.start_span(params[:span_name])
    set_llm_turn_request_attributes(span, params)
    set_llm_turn_prompt_attributes(span, params[:messages]) if params[:messages]

    @pending_llm_turn_spans ||= []
    @pending_llm_turn_spans.push(span)
  rescue StandardError => e
    Rails.logger.warn "Failed to start LLM turn span: #{e.message}"
  end

  def end_llm_turn_span(message)
    return unless ChatwootApp.otel_enabled?

    span = @pending_llm_turn_spans&.pop
    return unless span

    set_llm_turn_response_attributes(span, message) if message
    span.finish
  rescue StandardError => e
    Rails.logger.warn "Failed to end LLM turn span: #{e.message}"
  end

  private

  def set_llm_turn_request_attributes(span, params)
    provider = determine_provider(params[:model])
    span.set_attribute(ATTR_GEN_AI_PROVIDER, provider)
    span.set_attribute(ATTR_GEN_AI_REQUEST_MODEL, params[:model]) if params[:model]
    span.set_attribute(ATTR_GEN_AI_REQUEST_TEMPERATURE, params[:temperature]) if params[:temperature]
  end

  def set_llm_turn_prompt_attributes(span, messages)
    messages.each_with_index do |msg, idx|
      span.set_attribute(format(ATTR_GEN_AI_PROMPT_ROLE, idx), msg[:role])
      span.set_attribute(format(ATTR_GEN_AI_PROMPT_CONTENT, idx), msg[:content])
    end
    span.set_attribute(ATTR_LANGFUSE_OBSERVATION_INPUT, messages.to_json)
  end

  def set_llm_turn_response_attributes(span, message)
    span.set_attribute(ATTR_GEN_AI_COMPLETION_ROLE, message.role.to_s) if message.respond_to?(:role)
    span.set_attribute(ATTR_GEN_AI_COMPLETION_CONTENT, message.content.to_s) if message.respond_to?(:content)
    set_llm_turn_usage_attributes(span, message)
    span.set_attribute(ATTR_LANGFUSE_OBSERVATION_OUTPUT, message.content.to_s) if message.respond_to?(:content)
  end

  def set_llm_turn_usage_attributes(span, message)
    span.set_attribute(ATTR_GEN_AI_USAGE_INPUT_TOKENS, message.input_tokens) if message.respond_to?(:input_tokens) && message.input_tokens
    span.set_attribute(ATTR_GEN_AI_USAGE_OUTPUT_TOKENS, message.output_tokens) if message.respond_to?(:output_tokens) && message.output_tokens
  end
end
