class EnqueueRetrainAiAgentsJob < ActiveRecord::Migration[7.1]
  def up
    Migration::RetrainAiAgentsJob.perform_later
  end

  def down; end
end
