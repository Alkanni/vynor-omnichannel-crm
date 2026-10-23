class AddTrainedAtToAiAgents < ActiveRecord::Migration[7.1]
  def change
    add_column :ai_agents, :trained_at, :datetime
  end
end
