class AiAgents::IndexKnowledgeJob < ApplicationJob
  queue_as :low

  LOCK_TIMEOUT = 1.hour
  RETRY_DELAY = 30.seconds

  def perform(ai_agent)
    lock_key = format(Redis::Alfred::AI_AGENT_TRAINING_LOCK, id: ai_agent.id)
    lock_manager = Redis::LockManager.new
    return self.class.set(wait: RETRY_DELAY).perform_later(ai_agent) unless lock_manager.lock(lock_key, LOCK_TIMEOUT)

    begin
      # Changes made from here on queue a new job, which runs once this one releases the lock.
      Redis::Alfred.delete(format(Redis::Alfred::AI_AGENT_TRAINING_SCHEDULED, id: ai_agent.id))
      AiAgents::KnowledgeIndexer.new(ai_agent: ai_agent).perform
    ensure
      lock_manager.unlock(lock_key)
    end
  end
end
