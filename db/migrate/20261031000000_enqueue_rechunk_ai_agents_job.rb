class EnqueueRechunkAiAgentsJob < ActiveRecord::Migration[7.1]
  def up
    Migration::RechunkAiAgentsJob.perform_later
  end

  def down; end
end
