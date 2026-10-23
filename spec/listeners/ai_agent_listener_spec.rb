require 'rails_helper'

describe AiAgentListener do
  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:ai_agent) { create(:ai_agent, account: account, welcome_message: 'Halo! Ada yang bisa kami bantu?', message_await: 7) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:message_attributes) { { account: account, inbox: inbox, conversation: conversation } }

  before { create(:ai_agent_inbox, ai_agent: ai_agent, inbox: inbox) }

  describe '#conversation_created' do
    let(:event) { Events::Base.new('conversation.created', Time.zone.now, conversation: conversation) }

    it 'sends the welcome message from the AI agent' do
      listener.conversation_created(event)

      expect(conversation.messages.outgoing.where(sender: ai_agent).pluck(:content)).to eq(['Halo! Ada yang bisa kami bantu?'])
    end

    it 'does not send a welcome message when the agent has none' do
      ai_agent.update!(welcome_message: '')

      listener.conversation_created(event)

      expect(conversation.messages).to be_empty
    end

    it 'does not greet conversations of inboxes without an AI agent' do
      other_conversation = create(:conversation, account: account)

      listener.conversation_created(Events::Base.new('conversation.created', Time.zone.now, conversation: other_conversation))

      expect(other_conversation.messages).to be_empty
    end
  end

  describe '#message_created' do
    it 'schedules a reply after the message await delay' do
      message = create(:message, **message_attributes)

      freeze_time do
        expect { listener.message_created(Events::Base.new('message.created', Time.zone.now, message: message)) }
          .to have_enqueued_job(AiAgents::ReplyJob).with(message).at(7.seconds.from_now)
      end
    end

    it 'ignores outgoing messages, private notes, and conversations that are not pending' do
      outgoing = create(:message, **message_attributes, message_type: :outgoing)
      note = create(:message, **message_attributes, message_type: :outgoing, private: true)
      open_conversation = create(:conversation, account: account, inbox: inbox).tap(&:open!)
      incoming_on_open = create(:message, account: account, inbox: inbox, conversation: open_conversation)

      expect do
        [outgoing, note, incoming_on_open].each do |message|
          listener.message_created(Events::Base.new('message.created', Time.zone.now, message: message))
        end
      end.not_to have_enqueued_job(AiAgents::ReplyJob)
    end

    it 'ignores inboxes without an AI agent' do
      message = create(:message, account: account)

      expect { listener.message_created(Events::Base.new('message.created', Time.zone.now, message: message)) }
        .not_to have_enqueued_job(AiAgents::ReplyJob)
    end

    context 'when the AI handed the conversation off' do
      let(:message) { create(:message, **message_attributes, content: 'Halo, masih menunggu') }
      # Reloaded like the dispatched event, so the inbox reads the agent settings changed below.
      let(:event) { Events::Base.new('message.created', Time.zone.now, message: message.reload) }

      before do
        ai_agent.update!(pending_unassigned_message: 'Mohon tunggu, agen kami segera membalas.')
        AiAgents::ConversationSession.new(conversation: conversation, ai_agent: ai_agent).handoff!(:transfer_conditions)
      end

      it 'sends the pending message instead of a reply' do
        expect { listener.message_created(event) }.not_to have_enqueued_job(AiAgents::ReplyJob)
        expect(conversation.messages.outgoing.where(sender: ai_agent).pluck(:content)).to eq(['Mohon tunggu, agen kami segera membalas.'])
      end

      it 'schedules a reply when Stop AI after Handoff is off' do
        ai_agent.update!(stop_ai_after_handoff: false)

        expect { listener.message_created(event) }.to have_enqueued_job(AiAgents::ReplyJob).with(message)
        expect(conversation.messages.outgoing.where(sender: ai_agent)).to be_empty
      end
    end
  end
end
