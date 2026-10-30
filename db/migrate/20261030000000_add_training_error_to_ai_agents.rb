class AddTrainingErrorToAiAgents < ActiveRecord::Migration[7.1]
  def change
    add_column :ai_agents, :training_error, :string
    add_column :ai_agents, :training_failed_at, :datetime
  end
end
