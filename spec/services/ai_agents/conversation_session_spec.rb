require 'rails_helper'

RSpec.describe AiAgents::ConversationSession do
  let(:account) { create(:account) }
  let(:ai_agent) { create(:ai_agent, account: account, history_limit: 3) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:session) { described_class.new(conversation: conversation, ai_agent: ai_agent) }

  let(:message_attributes) { { account: account, inbox: inbox, conversation: conversation } }

  before { create(:ai_agent_inbox, ai_agent: ai_agent, inbox: inbox) }

  describe '#history' do
    it 'returns the latest messages up to the history limit, oldest first' do
      create(:message, **message_attributes, content: 'Halo')
      create(:message, **message_attributes, message_type: :outgoing, content: 'Halo juga')
      create(:message, **message_attributes, message_type: :outgoing, private: true, content: 'Catatan internal')
      create(:message, **message_attributes, content: 'Jam buka?')
      create(:message, **message_attributes, content: 'Hari ini?')

      expect(session.history.map { |entry| entry.slice(:role, :content) }).to eq(
        [{ role: :assistant, content: 'Halo juga' }, { role: :user, content: 'Jam buka?' }, { role: :user, content: 'Hari ini?' }]
      )
    end

    it 'keeps only the current session when session-only memory is on' do
      create(:message, **message_attributes, content: 'Pertanyaan lama')
      create(:reporting_event, name: 'conversation_resolved', account: account, inbox: inbox, conversation: conversation,
                               event_end_time: Time.current)
      create(:message, **message_attributes, content: 'Pertanyaan baru')

      expect(session.history.pluck(:content)).to eq(['Pertanyaan lama', 'Pertanyaan baru'])
      ai_agent.update!(session_only_memory: true)
      expect(session.history.pluck(:content)).to eq(['Pertanyaan baru'])
    end

    it 'attaches images only from the messages within the read file limit' do
      ai_agent.update!(read_file_limit: 1)
      create(:message, :with_attachment, **message_attributes, content: 'Foto lama')
      create(:message, :with_attachment, **message_attributes, content: 'Foto baru')

      attachments = session.history.pluck(:attachments)

      expect(attachments.first).to be_empty
      expect(attachments.last).to contain_exactly(an_instance_of(ActiveStorage::Blob))
    end
  end

  describe '#reply_count' do
    it 'counts AI replies in the current session, not their bubbles' do
      first = create(:message, **message_attributes, content: 'Halo')
      2.times { |index| session.reply!("Bubble #{index}", to: first) }
      session.reply!('Balasan kedua', to: create(:message, **message_attributes, content: 'Lagi'))

      expect(session.reply_count).to eq(2)

      create(:reporting_event, name: 'conversation_resolved', account: account, inbox: inbox, conversation: conversation,
                               event_end_time: Time.current)
      expect(session.reply_count).to eq(0)
    end
  end
end
