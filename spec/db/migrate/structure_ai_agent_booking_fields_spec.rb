require 'rails_helper'
require Rails.root.join('db/migrate/20261127000000_structure_ai_agent_booking_fields')

RSpec.describe StructureAiAgentBookingFields do
  let(:migration) { described_class.new.tap { |migration| migration.verbose = false } }
  let(:connection) { ActiveRecord::Base.connection }
  let(:plate) { { 'name' => 'Plat nomor', 'description' => 'Contoh: D 1234 ABC', 'type' => 'text', 'options' => [], 'required' => true } }
  let(:car) { { 'name' => 'Mobil', 'description' => '', 'type' => 'choice', 'options' => %w[Avanza Xenia], 'required' => false } }
  let!(:ai_agent) { create(:ai_agent, booking_fields: [plate, car], booking_services: ['Servis berkala']) }
  let!(:without_fields) { create(:ai_agent) }

  after { AiAgent.reset_column_information }

  it 'keeps only the field names going down, and turns each name into a plain text field going up' do
    migration.migrate(:down)
    AiAgent.reset_column_information

    expect(connection.select_rows('SELECT id, booking_fields FROM ai_agents ORDER BY id').to_h.transform_values { |fields| JSON.parse(fields) })
      .to eq(ai_agent.id => ['Plat nomor', 'Mobil'], without_fields.id => [])
    expect(connection.column_exists?(:ai_agents, :booking_services)).to be(false)

    migration.migrate(:up)
    AiAgent.reset_column_information

    plain = { 'description' => '', 'type' => 'text', 'options' => [], 'required' => false }
    expect(ai_agent.reload).to have_attributes(booking_fields: [plain.merge('name' => 'Plat nomor'), plain.merge('name' => 'Mobil')],
                                               booking_services: [])
    expect(ai_agent).to be_valid
    expect(without_fields.reload).to have_attributes(booking_fields: [], booking_services: [])
  end
end
