# Deletes the AI Agent request logs older than AiAgent::RequestLog::RETENTION, in batches, every day (see config/schedule.yml).
class AiAgents::RemoveOldRequestLogsJob < ApplicationJob
  queue_as :purgable

  BATCH_SIZE = 1_000

  def perform
    AiAgent::RequestLog.where(created_at: ...AiAgent::RequestLog::RETENTION.ago).in_batches(of: BATCH_SIZE).delete_all
  end
end
