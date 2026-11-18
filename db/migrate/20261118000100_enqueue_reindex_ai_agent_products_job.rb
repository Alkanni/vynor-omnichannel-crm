class EnqueueReindexAiAgentProductsJob < ActiveRecord::Migration[7.1]
  def up
    Migration::ReindexAiAgentProductsJob.perform_later
  end

  def down; end
end
