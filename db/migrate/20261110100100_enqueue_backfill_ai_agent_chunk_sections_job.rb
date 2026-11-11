class EnqueueBackfillAiAgentChunkSectionsJob < ActiveRecord::Migration[7.1]
  def up
    Migration::BackfillAiAgentChunkSectionsJob.perform_later
  end

  def down; end
end
