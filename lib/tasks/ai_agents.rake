namespace :ai_agents do
  desc 'Print the AI Agent usage of a period as Markdown (see AiAgents::UsageReport). FROM and TO are ISO 8601 dates or times, UTC ' \
       'unless they have an offset, and default to the 7 days up to now; TO is left out. AGENT_ID limits it to one agent.'
  task usage_report: :environment do
    to = ENV.fetch('TO', nil)&.then { |time| Time.zone.iso8601(time) } || Time.current
    from = ENV.fetch('FROM', nil)&.then { |time| Time.zone.iso8601(time) } || (to - 7.days)
    ai_agent_id = ENV.fetch('AGENT_ID', nil)&.then { |id| Integer(id) }
    puts AiAgents::UsageReport.new(from: from, to: to, ai_agent_id: ai_agent_id).perform
  end
end
