require 'rails_helper'

RSpec.describe Rake::Task do
  describe 'ai_agents:usage_report' do
    subject(:task) { described_class['ai_agents:usage_report'] }

    let(:ai_agent) { create(:ai_agent, name: 'CS Toko Roti') }

    before do
      task.reenable
      create(:ai_agent_reply_trace, ai_agent: create(:ai_agent, name: 'CS Bengkel'), created_at: Time.utc(2026, 11, 2))
      create(:ai_agent_reply_trace, ai_agent: ai_agent, created_at: Time.utc(2026, 11, 2), input_tokens: 1200, output_tokens: 40)
    end

    it 'prints the report of the period and the agent given' do
      with_modified_env FROM: '2026-11-01', TO: '2026-11-03T00:00:00+07:00', AGENT_ID: ai_agent.id.to_s do
        expect { task.invoke }.to output(
          a_string_starting_with("# AI Agent usage from 2026-11-01T00:00:00Z to 2026-11-02T17:00:00Z\n\n## CS Toko Roti (id #{ai_agent.id})")
        ).to_stdout
      end
    end

    it 'reports the 7 days up to now for all agents by default' do
      travel_to(Time.utc(2026, 11, 4, 12)) do
        with_modified_env FROM: nil, TO: nil, AGENT_ID: nil do
          expect { task.invoke }.to output(
            a_string_starting_with("# AI Agent usage from 2026-10-28T12:00:00Z to 2026-11-04T12:00:00Z\n\n## CS Bengkel")
              .and(a_string_including("## CS Toko Roti (id #{ai_agent.id})"))
          ).to_stdout
        end
      end
    end

    it 'rejects a period or an agent id in another format' do
      with_modified_env FROM: '1 November 2026' do
        expect { task.invoke }.to raise_error(ArgumentError)
      end
      task.reenable
      with_modified_env AGENT_ID: 'toko-roti' do
        expect { task.invoke }.to raise_error(ArgumentError)
      end
    end
  end
end
