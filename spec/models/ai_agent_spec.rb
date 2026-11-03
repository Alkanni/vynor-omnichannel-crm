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
        ignore_team_handoff: false, allowed_label_ids: [], scope_mode: 'off', scope_policy_version: 0
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
        label_conditions: 'a' * 3_001, pending_assigned_message: 'a' * 201, pending_unassigned_message: 'a' * 201,
        business_description: 'a' * 3_001, allowed_topics: 'a' * 3_001, disallowed_topics: 'a' * 3_001
      )

      expect(ai_agent).not_to be_valid
      expect(ai_agent.errors.attribute_names).to contain_exactly(
        :behavior, :welcome_message, :transfer_conditions, :label_conditions,
        :pending_assigned_message, :pending_unassigned_message,
        :business_description, :allowed_topics, :disallowed_topics
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

    it 'rejects unknown temperature, timezone, and scope mode values' do
      ai_agent.assign_attributes(temperature: 'wild', timezone: 'Mars/Olympus', scope_mode: 'loose')

      expect(ai_agent).not_to be_valid
      expect(ai_agent.errors.attribute_names).to contain_exactly(:temperature, :timezone, :scope_mode)
    end

    it 'requires a business description, allowed topics, and the three scope replies in strict mode only' do
      ai_agent.assign_attributes(scope_mode: 'strict', business_description: "  \n", allowed_topics: '', off_topic_message: ' ')

      expect(ai_agent).not_to be_valid
      expect(ai_agent.errors.attribute_names)
        .to contain_exactly(:business_description, :allowed_topics, :off_topic_message, :clarification_message, :knowledge_gap_message)

      ai_agent.assign_attributes(business_description: 'Toko roti', allowed_topics: 'Harga', off_topic_message: 'Maaf, di luar layanan kami.',
                                 clarification_message: 'Produk yang mana, Kak?', knowledge_gap_message: 'Maaf, info itu belum ada.')
      expect(ai_agent).to be_valid

      ai_agent.assign_attributes(scope_mode: 'off', business_description: nil, allowed_topics: nil, off_topic_message: nil,
                                 clarification_message: nil, knowledge_gap_message: nil)
      expect(ai_agent).to be_valid
    end

    it 'limits the scope replies to 1,000 characters' do
      ai_agent.assign_attributes(off_topic_message: 'a' * 1_001, clarification_message: 'a' * 1_000, knowledge_gap_message: 'a' * 1_001)

      expect(ai_agent).not_to be_valid
      expect(ai_agent.errors.attribute_names).to contain_exactly(:off_topic_message, :knowledge_gap_message)
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

    context 'when gateway models are configured' do
      before { create(:installation_config, name: 'AI_AGENT_MODELS', value: ' cx/gpt-5.5, cx/gpt-5.4-mini,,cx/gpt-5.5 ') }

      it 'accepts only those models and defaults new agents to the first one' do
        expect(described_class.new.model).to eq('cx/gpt-5.5')
        expect(described_class.available_models).to eq([{ id: 'cx/gpt-5.5', display_name: 'cx/gpt-5.5' },
                                                        { id: 'cx/gpt-5.4-mini', display_name: 'cx/gpt-5.4-mini' }])

        ai_agent.model = 'cx/gpt-5.4-mini'
        expect(ai_agent).to be_valid
        ai_agent.model = 'gpt-4.1'
        expect(ai_agent).not_to be_valid
      end
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

  describe '#knowledge_stats' do
    it 'counts characters of every manual knowledge source' do
      ai_agent.save!
      create(:ai_agent_knowledge_source, ai_agent: ai_agent, content: 'a' * 10)
      create(:ai_agent_knowledge_source, ai_agent: ai_agent, content: nil)
      create(:ai_agent_knowledge_source, :qa, ai_agent: ai_agent, title: 'q' * 3, content: 'a' * 4)
      create(:ai_agent_product, ai_agent: ai_agent, name: 'n' * 5, description: 'd' * 6)

      create(:ai_agent_knowledge_source, ai_agent: ai_agent, source_type: :website, external_url: 'https://grandsehat.example.com',
                                         content: 'w' * 8)

      expect(ai_agent.knowledge_stats).to eq(
        files: 0, links: 1, text_characters: 10, qa_count: 1, qa_characters: 7, products: 1, total_characters: 36
      )
    end
  end

  describe 'scope policy version' do
    before { ai_agent.save! }

    it 'goes up by one when a policy attribute changes' do
      { business_description: 'Toko roti', allowed_topics: 'Harga', disallowed_topics: 'Politik', off_topic_message: 'Maaf.',
        clarification_message: 'Yang mana?', knowledge_gap_message: 'Belum ada info.', scope_mode: 'strict' }.each do |attribute, value|
        expect { ai_agent.update!(attribute => value) }.to change(ai_agent, :scope_policy_version).by(1)
      end
    end

    it 'goes up once when a save changes several policy attributes' do
      expect do
        ai_agent.update!(scope_mode: 'strict', business_description: 'Toko roti', allowed_topics: 'Harga', off_topic_message: 'Maaf.',
                         clarification_message: 'Yang mana?', knowledge_gap_message: 'Belum ada info.')
      end.to change(ai_agent, :scope_policy_version).by(1)
    end

    it 'stays when other settings change' do
      expect { ai_agent.update!(behavior: 'Jawab singkat.', message_limit: 20) }.not_to change(ai_agent, :scope_policy_version)
    end

    it 'stays when the settings form sends unset or padded policy fields' do
      ai_agent.update!(business_description: 'Toko roti')

      expect do
        ai_agent.update!(business_description: " Toko roti\n", allowed_topics: '', disallowed_topics: ' ', off_topic_message: '',
                         clarification_message: "\n", knowledge_gap_message: ' ', name: 'Baru')
      end.not_to change(ai_agent, :scope_policy_version)
      expect(ai_agent.reload).to have_attributes(business_description: 'Toko roti', allowed_topics: nil, disallowed_topics: nil,
                                                 off_topic_message: nil, clarification_message: nil, knowledge_gap_message: nil)
    end
  end

  describe '#duplicate!' do
    it 'copies knowledge sources and products including images' do
      ai_agent.save!
      create(:ai_agent_knowledge_source, ai_agent: ai_agent, title: 'Default', content: 'Sejarah Grand Sehat')
      create(:ai_agent_knowledge_source, :qa, ai_agent: ai_agent)
      product = build(:ai_agent_product, ai_agent: ai_agent, name: 'Balance arm')
      product.image.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'avatar.png', content_type: 'image/png')
      product.save!

      copy = ai_agent.duplicate!

      expect(copy.knowledge_sources.pluck(:source_type, :title)).to match_array(ai_agent.knowledge_sources.pluck(:source_type, :title))
      expect(copy.products.pluck(:name, :price, :weight, :stock)).to eq(ai_agent.products.pluck(:name, :price, :weight, :stock))
      copied_image = copy.products.first.image
      expect(copied_image).to be_attached
      expect(copied_image.blob_id).not_to eq(product.image.blob_id)
    end

    it 'starts the copy untrained, without the indexing error of the original' do
      ai_agent.update!(trained_at: 1.day.ago, training_error: 'The AI model request failed (TimeoutError)', training_failed_at: 1.hour.ago)

      expect(ai_agent.duplicate!).to have_attributes(trained_at: nil, training_error: nil, training_failed_at: nil)
    end

    it 'copies the settings under a new name' do
      label = create(:label, account: account)
      ai_agent.update!(welcome_message: 'Halo', allowed_label_ids: [label.id], history_limit: 12, temperature: 'creative', scope_mode: 'strict',
                       business_description: 'Toko roti', allowed_topics: 'Harga', disallowed_topics: 'Politik', off_topic_message: 'Maaf.',
                       clarification_message: 'Yang mana?', knowledge_gap_message: 'Belum ada info.')

      copy = ai_agent.duplicate!

      expect(copy).to be_persisted
      expect(copy.id).not_to eq(ai_agent.id)
      expect(copy.name).to eq("#{ai_agent.name} (Copy)")
      expect(copy.attributes.except('id', 'name', 'created_at', 'updated_at'))
        .to eq(ai_agent.attributes.except('id', 'name', 'created_at', 'updated_at'))
    end

    it 'does not copy the inbox connections or the training time' do
      ai_agent.update!(trained_at: Time.current)
      create(:ai_agent_inbox, ai_agent: ai_agent)

      copy = ai_agent.duplicate!

      expect(copy.inboxes).to be_empty
      expect(copy.trained_at).to be_nil
    end
  end

  describe '#schedule_training' do
    before do
      ai_agent.save!
      Redis::Alfred.delete(format(Redis::Alfred::AI_AGENT_TRAINING_SCHEDULED, id: ai_agent.id))
    end

    after { Redis::Alfred.delete(format(Redis::Alfred::AI_AGENT_TRAINING_SCHEDULED, id: ai_agent.id)) }

    it 'queues one indexing job for a burst of knowledge changes' do
      expect do
        create(:ai_agent_knowledge_source, ai_agent: ai_agent)
        create(:ai_agent_knowledge_source, :qa, ai_agent: ai_agent)
        create(:ai_agent_product, ai_agent: ai_agent)
      end.to have_enqueued_job(AiAgents::IndexKnowledgeJob).with(ai_agent).exactly(:once)
    end
  end
end
