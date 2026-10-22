require 'rails_helper'

RSpec.describe AiAgent do
  let(:account) { create(:account) }
  let(:ai_agent) { build(:ai_agent, account: account) }

  describe 'defaults' do
    it 'uses the assistant default model and the documented settings' do
      expect(ai_agent).to have_attributes(
        model: Llm::Models.default_model_for('assistant'),
        stop_ai_after_handoff: true, silent_handoff: false, history_limit: 30, read_file_limit: 3,
        context_limit: 40, temperature: 'balanced', message_await: 10, message_limit: 10,
        watcher_enabled: false, timezone: 'Asia/Jakarta', session_only_memory: false,
        ignore_team_handoff: false, allowed_label_ids: []
      )
      expect(ai_agent).to be_valid
    end
  end

  describe 'validations' do
    it 'requires a name' do
      ai_agent.name = ''
      expect(ai_agent).not_to be_valid
    end

    it 'enforces text length limits' do
      ai_agent.assign_attributes(
        behavior: 'a' * 15_001, welcome_message: 'a' * 5_001, transfer_conditions: 'a' * 3_001,
        label_conditions: 'a' * 3_001, pending_assigned_message: 'a' * 201, pending_unassigned_message: 'a' * 201
      )

      expect(ai_agent).not_to be_valid
      expect(ai_agent.errors.attribute_names).to contain_exactly(
        :behavior, :welcome_message, :transfer_conditions, :label_conditions,
        :pending_assigned_message, :pending_unassigned_message
      )
    end

    it 'accepts text at the length limits' do
      ai_agent.assign_attributes(behavior: 'a' * 15_000, welcome_message: 'a' * 5_000, pending_assigned_message: 'a' * 200)
      expect(ai_agent).to be_valid
    end

    it 'enforces numeric ranges' do
      ai_agent.assign_attributes(history_limit: 0, read_file_limit: 11, context_limit: 101, message_await: -1, message_limit: 1001)

      expect(ai_agent).not_to be_valid
      expect(ai_agent.errors.attribute_names).to contain_exactly(
        :history_limit, :read_file_limit, :context_limit, :message_await, :message_limit
      )
    end

    it 'rejects unknown temperature and timezone values' do
      ai_agent.assign_attributes(temperature: 'wild', timezone: 'Mars/Olympus')

      expect(ai_agent).not_to be_valid
      expect(ai_agent.errors.attribute_names).to contain_exactly(:temperature, :timezone)
    end

    it 'rejects models outside the assistant feature' do
      ai_agent.model = 'whisper-1'
      expect(ai_agent).not_to be_valid
      expect(ai_agent.errors.attribute_names).to eq([:model])
    end

    it 'rejects coming soon models' do
      ai_agent.model = 'claude-sonnet-4.5'
      expect(ai_agent).not_to be_valid
    end

    it 'accepts labels of the same account only' do
      own_label = create(:label, account: account)
      other_label = create(:label)

      ai_agent.allowed_label_ids = [own_label.id]
      expect(ai_agent).to be_valid

      ai_agent.allowed_label_ids = [own_label.id, other_label.id]
      expect(ai_agent).not_to be_valid
      expect(ai_agent.errors.attribute_names).to eq([:allowed_label_ids])
    end

    it 'rejects non integer label ids' do
      ai_agent.allowed_label_ids = ['1']
      expect(ai_agent).not_to be_valid
    end
  end

  describe '#duplicate!' do
    it 'copies the settings under a new name' do
      label = create(:label, account: account)
      ai_agent.update!(welcome_message: 'Halo', allowed_label_ids: [label.id], history_limit: 12, temperature: 'creative')

      copy = ai_agent.duplicate!

      expect(copy).to be_persisted
      expect(copy.id).not_to eq(ai_agent.id)
      expect(copy.name).to eq("#{ai_agent.name} (Copy)")
      expect(copy.attributes.except('id', 'name', 'created_at', 'updated_at'))
        .to eq(ai_agent.attributes.except('id', 'name', 'created_at', 'updated_at'))
    end
  end
end
