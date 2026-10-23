require 'rails_helper'

RSpec.describe AiAgents::AppendSheetRowJob do
  include_context 'with active record encryption'

  let(:account) { create(:account) }
  let(:ai_agent) { create(:ai_agent, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let!(:integration) { create(:ai_agent_integration, ai_agent: ai_agent) }
  let(:row) { ['Budi', '', '24 Oktober 2026'] }
  let(:append_url) { %r{https://sheets.googleapis.com/v4/spreadsheets/sheet-123/values/.+:append} }
  let(:sheet_activities) { conversation.messages.activity.where("additional_attributes ->> 'ai_agent_sheet_row' IS NOT NULL") }

  before { create(:ai_agent_inbox, ai_agent: ai_agent, inbox: inbox) }

  it 'appends the row and records it on the conversation, once' do
    append = stub_request(:post, append_url).to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: '{}')

    2.times { described_class.perform_now(conversation, row) }

    expect(append).to have_been_requested.once
    expect(sheet_activities.sole).to have_attributes(content: "#{ai_agent.name} added a row to Google Sheets",
                                                     additional_attributes: { 'ai_agent_sheet_row' => row })
  end

  it 'writes nothing once the integration is disconnected or needs a reconnect' do
    integration.needs_reconnect!

    described_class.perform_now(conversation, row)

    expect(a_request(:post, append_url)).not_to have_been_made
    expect(sheet_activities).to be_empty
  end

  it 'asks for a reconnect and reports when the sheet is gone' do
    stub_request(:post, append_url).to_return(status: 404, headers: { 'Content-Type' => 'application/json' }, body: '{}')
    tracker = instance_double(ChatwootExceptionTracker, capture_exception: true)
    allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)

    described_class.perform_now(conversation, row)

    expect(integration.reload).to be_needs_reconnect
    expect(tracker).to have_received(:capture_exception)
    expect(sheet_activities).to be_empty
  end

  it 'leaves transient Google errors to the job retry' do
    stub_request(:post, append_url).to_return(status: 503, headers: { 'Content-Type' => 'application/json' }, body: '{}')

    expect { described_class.perform_now(conversation, row) }.to raise_error(AiAgents::GoogleSheetsError)
    expect(integration.reload).to be_connected
  end
end
