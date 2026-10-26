# The function an AI Agent answers through: AiAgents::LlmClient#chat forces the model to call it and returns its
# arguments, so the call stops there instead of running a tool loop.
class AiAgents::ReplyTool < RubyLLM::Tool
  attr_reader :name, :params_schema

  def initialize(name:, schema:)
    super()
    @name = name
    @params_schema = schema
  end

  def description = 'Submit the response.'

  def execute(**arguments) = halt(arguments)
end
