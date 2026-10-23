require 'rails_helper'

RSpec.describe AiAgents::ActionSchema do
  include_context 'with active record encryption'

  let(:ai_agent) { create(:ai_agent) }
  let(:schema) { described_class.new(ai_agent: ai_agent, written_rows: [['Ani', '', '1 Oktober']]) }

  context 'with a writable Google Sheets integration' do
    before { create(:ai_agent_integration, ai_agent: ai_agent) }

    it 'asks for a row with one field per named column and lists the rows already written' do
      properties = schema.json_schema('ai_agent_reply')[:schema][:properties]

      expect(properties[:write_sheet_row]).to eq(type: 'boolean')
      expect(properties[:sheet_row]).to eq(type: 'object', properties: { 'Nama' => { type: 'string' }, 'Tanggal' => { type: 'string' } },
                                           required: %w[Nama Tanggal], additionalProperties: false)
      expect(schema.instructions).to include('Saat customer sudah mengisi format booking lengkap', 'Columns: Nama, Tanggal',
                                             '["Ani","","1 Oktober"]')
    end

    it 'returns the row in header order, with blanks for unnamed columns, only when asked to write' do
      expect(schema.parse('write_sheet_row' => true, 'sheet_row' => { 'Tanggal' => ' 24 Oktober ', 'Nama' => 'Budi' })[:sheet_row])
        .to eq(['Budi', '', '24 Oktober'])
      expect(schema.parse('write_sheet_row' => false, 'sheet_row' => { 'Nama' => 'Budi', 'Tanggal' => '' })[:sheet_row]).to be_nil
      expect(schema.parse('write_sheet_row' => true, 'sheet_row' => { 'Nama' => '', 'Tanggal' => '' })[:sheet_row]).to be_nil
    end
  end

  it 'leaves the sheet out when the integration cannot write' do
    create(:ai_agent_integration, ai_agent: ai_agent, status: :needs_reconnect)

    expect(schema).not_to be_any
    expect(schema.parse('write_sheet_row' => true, 'sheet_row' => { 'Nama' => 'Budi' })[:sheet_row]).to be_nil
  end
end
