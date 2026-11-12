require 'rails_helper'

RSpec.describe AiAgents::RemoveOldRequestLogsJob do
  let(:ai_agent) { create(:ai_agent) }

  it 'deletes the request logs older than 30 days and keeps the newer ones' do
    old, recent = [31.days.ago, 29.days.ago].map do |created_at|
      AiAgent::RequestLog.create!(account: ai_agent.account, ai_agent: ai_agent, source: :reply, status: :ok, created_at: created_at)
    end

    described_class.perform_now

    expect(AiAgent::RequestLog.all).to eq([recent])
    expect { old.reload }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'runs every day' do
    expect(YAML.load_file(Rails.root.join('config/schedule.yml'))['remove_old_ai_agent_request_logs_job'])
      .to eq('cron' => '0 20 * * *', 'class' => described_class.name, 'queue' => 'purgable')
  end
end
