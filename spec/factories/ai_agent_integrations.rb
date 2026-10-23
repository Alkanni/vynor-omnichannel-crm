# frozen_string_literal: true

FactoryBot.define do
  factory :ai_agent_integration, class: 'AiAgent::Integration' do
    ai_agent
    integration_type { 'google_sheets' }
    credentials { { 'access_token' => 'ya29.access-token', 'refresh_token' => '1//refresh-token', 'expires_at' => 1.hour.from_now.to_i } }
    settings do
      { 'email' => 'owner@example.com', 'spreadsheet_url' => 'https://docs.google.com/spreadsheets/d/sheet-123/edit',
        'spreadsheet_id' => 'sheet-123', 'sheet_name' => 'Booking', 'columns' => ['Nama', '', 'Tanggal'],
        'when_to_write' => 'Saat customer sudah mengisi format booking lengkap' }
    end
  end
end
