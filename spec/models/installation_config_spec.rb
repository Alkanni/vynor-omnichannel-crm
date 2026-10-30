# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InstallationConfig do
  subject(:installation_config) { described_class.new(name: 'INSTALLATION_NAME') }

  it { is_expected.to validate_presence_of(:name) }

  describe 'new record defaults' do
    it 'initializes serialized_value with indifferent access' do
      expect(installation_config.serialized_value).to eq({}.with_indifferent_access)
    end

    it 'returns nil for value before assignment' do
      expect(installation_config.value).to be_nil
    end
  end

  describe 'AI_AGENT_EMBEDDING_MAX_DISTANCE' do
    it 'accepts a blank value or a cosine distance above 0 and up to 2' do
      ['', '0.85', '2', 0.5].each do |value|
        expect(described_class.new(name: 'AI_AGENT_EMBEDDING_MAX_DISTANCE', value: value)).to be_valid
      end
    end

    it 'rejects anything else' do
      ['0', '-0.1', '2.5', 'abc'].each do |value|
        config = described_class.new(name: 'AI_AGENT_EMBEDDING_MAX_DISTANCE', value: value)

        expect(config).not_to be_valid
        expect(config.errors[:base]).to eq(['AI Agent Max Embedding Distance must be a number greater than 0 and at most 2'])
      end
    end
  end
end
