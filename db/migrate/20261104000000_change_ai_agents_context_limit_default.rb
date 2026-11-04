class ChangeAiAgentsContextLimitDefault < ActiveRecord::Migration[7.1]
  # The Context Limit now only sets how many knowledge chunks reach the model (#103). In evals/ai-agent 8 chunks answered
  # as well as 40 with about half the input tokens, so agents still on the old default move to the new one; agents with
  # another limit keep it. Rolling back also moves agents set to 8 by hand back to 40.
  def up
    change_column_default :ai_agents, :context_limit, from: 40, to: 8
    execute 'UPDATE ai_agents SET context_limit = 8 WHERE context_limit = 40'
  end

  def down
    change_column_default :ai_agents, :context_limit, from: 8, to: 40
    execute 'UPDATE ai_agents SET context_limit = 40 WHERE context_limit = 8'
  end
end
