require 'rails_helper'

RSpec.describe AiAgents::ReplyJob do
  let(:account) { create(:account) }
  let(:ai_agent) { create(:ai_agent, account: account, message_limit: 2) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:message_attributes) { { account: account, inbox: inbox, conversation: conversation } }
  let(:trace) do
    chunk = AiAgent::KnowledgeChunk.new(id: 7, chunkable_type: 'AiAgent::KnowledgeSource', chunkable_id: 3)
    retrieval = AiAgents::KnowledgeRetriever::Result.new(mode: 'hybrid', embedding_model: 'text-embedding-3-small', queries: ['Jam buka?'],
                                                         hits: [AiAgents::KnowledgeRetriever::Hit.new(chunk: chunk, rank: 1, score: 0.12)])
    AiAgents::ReplyGenerator::Trace.new(scope: nil, retrieval: retrieval, web_search: nil, validation: nil, invalid_outputs: [], input_tokens: 120,
                                        output_tokens: 30, cached_input_tokens: 64, latency_ms: 850)
  end
  let(:traces) { AiAgent::ReplyTrace.where(conversation: conversation) }
  let(:reply) { AiAgents::ReplyGenerator::Reply.new(messages: ['Halo!', 'Ada yang bisa dibantu?'], handoff: false, labels: [], trace: trace) }
  let(:generator) { instance_double(AiAgents::ReplyGenerator, perform: reply) }
  let(:ai_replies) { conversation.messages.where(sender: ai_agent) }
  let(:handoff_activities) { conversation.messages.activity.where("additional_attributes ->> 'ai_agent_handoff' IS NOT NULL") }

  before do
    create(:ai_agent_inbox, ai_agent: ai_agent, inbox: inbox)
    allow(AiAgents::ReplyGenerator).to receive(:new).and_return(generator)
  end

  it 'sends each reply item as a separate message from the AI agent' do
    message = create(:message, **message_attributes, content: 'Halo')

    described_class.perform_now(message)

    expect(ai_replies.outgoing.pluck(:content)).to eq(['Halo!', 'Ada yang bisa dibantu?'])
    expect(ai_replies.map { |reply| reply.additional_attributes['ai_agent_reply_to'] }.uniq).to eq([message.id])
    expect(conversation.reload).to be_pending
  end

  it 'records a trace of the reply with the retrieved chunks as references' do
    message = create(:message, **message_attributes, content: 'Halo')

    described_class.perform_now(message)

    expect(traces.sole).to have_attributes(
      account_id: account.id, ai_agent_id: ai_agent.id, message_id: message.id, status: 'replied', model: ai_agent.model,
      retrieval_mode: 'hybrid', embedding_model: 'text-embedding-3-small', input_tokens: 120, output_tokens: 30, cached_input_tokens: 64,
      latency_ms: 850, labels: [], error_class: nil, scope_decision: nil, scope_latency_ms: nil, scope_input_tokens: nil, scope_output_tokens: nil,
      reply_decision: nil, cited_ranks: [], blocked_reason: nil, watcher_input_tokens: nil, watcher_output_tokens: nil,
      watcher_cached_input_tokens: nil, web_search_status: nil, web_results: [], web_latency_ms: nil, web_cost_usd: nil, invalid_outputs: [],
      retrieved: [{ 'chunk_id' => 7, 'chunkable_type' => 'AiAgent::KnowledgeSource', 'chunkable_id' => 3, 'rank' => 1, 'score' => 0.12,
                    'neighbor_of' => nil }]
    )
  end

  it 'records the web search of the reply with each result as its rank and URL, without the query or the page content' do
    scope = AiAgents::ScopeGuard::Result.new(decision: 'IN_SCOPE', web_query: 'penyebab aki cepat soak', web_search_status: 'pending',
                                             input_tokens: 900, output_tokens: 12, cached_input_tokens: nil, latency_ms: 700)
    item = AiAgents::WebSearch::Item.new(rank: 2, title: 'Aki soak', url: 'https://otomotif.example/aki', published_at: nil,
                                         highlights: ['Aki soak karena umur.'])
    web_search = AiAgents::WebSearch::Result.new(status: 'searched', results: [item], latency_ms: 610, cost_usd: 0.004)
    allow(generator).to receive(:perform).and_return(AiAgents::ReplyGenerator::Reply.new(
                                                       messages: ['Aki biasanya soak karena umur.'], handoff: false, labels: [],
                                                       trace: trace.with(scope: scope, web_search: web_search)
                                                     ))

    described_class.perform_now(create(:message, **message_attributes, content: 'Kenapa aki cepat soak?'))

    expect(traces.sole).to have_attributes(web_search_status: 'searched', web_results: [{ 'rank' => 2, 'url' => 'https://otomotif.example/aki' }],
                                           web_latency_ms: 610, web_cost_usd: BigDecimal('0.004'))
    expect(traces.sole.attributes.values.flatten.join).not_to include('penyebab aki cepat soak', 'Aki soak karena umur.')
  end

  it 'records the version of the scope policy the reply was made under' do
    ai_agent.update!(business_description: 'Toko roti')
    ai_agent.update!(allowed_topics: 'Harga')

    described_class.perform_now(create(:message, **message_attributes, content: 'Halo'))

    expect(traces.sole.scope_policy_version).to eq(2)
  end

  it 'answers a burst of messages once, from the job of the latest message' do
    messages = ['Halo', 'Mau tanya', 'Harga detailing?'].map { |content| create(:message, **message_attributes, content: content) }

    messages.each { |message| described_class.perform_now(message) }

    expect(AiAgents::ReplyGenerator).to have_received(:new).once
    expect(AiAgents::ReplyGenerator).to have_received(:new)
      .with(ai_agent: ai_agent, messages: array_including(hash_including(content: 'Halo'), hash_including(content: 'Harga detailing?')),
            written_rows: [], bookings: [])
    expect(ai_replies.count).to eq(2)
    expect(traces.sole.message).to eq(messages.last)
  end

  it 'drops the reply when the customer wrote again while it was generated' do
    message = create(:message, **message_attributes, content: 'Halo')
    allow(generator).to receive(:perform) do
      create(:message, **message_attributes, content: 'Masih di sana?')
      reply
    end

    described_class.perform_now(message)

    expect(ai_replies).to be_empty
    expect(traces).to be_empty
  end

  it 'does not answer conversations that are no longer pending' do
    message = create(:message, **message_attributes, content: 'Halo')
    conversation.open!

    described_class.perform_now(message)

    expect(AiAgents::ReplyGenerator).not_to have_received(:new)
    expect(ai_replies).to be_empty
  end

  it 'hands the conversation off once the AI message limit is reached in the session' do
    session = AiAgents::ConversationSession.new(conversation: conversation, ai_agent: ai_agent)
    2.times { session.reply!('Balasan', to: create(:message, **message_attributes)) }
    message = create(:message, **message_attributes, content: 'Pertanyaan ketiga')

    described_class.perform_now(message)

    expect(AiAgents::ReplyGenerator).not_to have_received(:new)
    expect(conversation.reload).to be_open
    expect(ai_replies.count).to eq(2)
    expect(handoff_activities.sole.additional_attributes).to eq('ai_agent_handoff' => 'message_limit')
    expect(traces.sole).to have_attributes(status: 'message_limit', message_id: message.id, retrieval_mode: nil, retrieved: [],
                                           input_tokens: nil, latency_ms: nil)
  end

  it 'hands the conversation off without replying when the model fails' do
    message = create(:message, **message_attributes, content: 'Halo')
    allow(generator).to receive(:perform).and_raise(AiAgents::LlmError, 'The AI model request failed (timeout)')
    tracker = instance_double(ChatwootExceptionTracker, capture_exception: true)
    allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)

    described_class.perform_now(message)

    expect(ai_replies).to be_empty
    expect(conversation.reload).to be_open
    expect(tracker).to have_received(:capture_exception)
    expect(handoff_activities.sole.additional_attributes).to eq('ai_agent_handoff' => 'error')
    expect(traces.sole).to have_attributes(status: 'error', error_class: 'AiAgents::LlmError', message_id: message.id, retrieved: [])
  end

  describe 'actions' do
    let(:message) { create(:message, **message_attributes, content: 'Saya mau komplain, sambungkan ke CS') }
    let(:reply) { AiAgents::ReplyGenerator::Reply.new(messages: ['Baik, kami sambungkan ke tim CS.'], handoff: true, labels: [], trace: trace) }

    before { allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original }

    it 'sends the transition note and hands the conversation off when the transfer conditions are met' do
      expect(conversation.reload.ai_assignee).to eq(ai_agent)

      described_class.perform_now(message)

      expect(ai_replies.pluck(:content)).to eq(['Baik, kami sambungkan ke tim CS.'])
      conversation.reload
      expect(conversation).to be_open
      expect(conversation.ai_assignee).to be_nil
      expect(handoff_activities.sole.content).to eq("#{ai_agent.name} handed the conversation over to a human agent (transfer conditions met)")
      expect(Rails.configuration.dispatcher).to have_received(:dispatch)
        .with(Events::Types::CONVERSATION_BOT_HANDOFF, anything, hash_including(conversation: conversation))
      expect(traces.sole).to have_attributes(status: 'handoff', message_id: message.id, retrieval_mode: 'hybrid')
    end

    it 'sends no AI message on a silent handoff' do
      ai_agent.update!(silent_handoff: true)

      described_class.perform_now(message)

      expect(ai_replies).to be_empty
      expect(conversation.reload).to be_open
    end

    it 'keeps the team at handoff so auto-assignment can pick a team member' do
      team = create(:team, account: account)
      conversation.update!(team: team)

      described_class.perform_now(message)

      expect(conversation.reload).to be_open
      expect(conversation.team).to eq(team)
    end

    it 'removes the team at handoff when Ignore Team Handoff is on' do
      ai_agent.update!(ignore_team_handoff: true)
      conversation.update!(team: create(:team, account: account))

      described_class.perform_now(message)

      expect(conversation.reload).to be_open
      expect(conversation.team).to be_nil
    end

    it 'adds the labels of the reply in the name of the AI agent' do
      create(:label, account: account, title: 'booking')
      allow(generator).to receive(:perform)
        .and_return(AiAgents::ReplyGenerator::Reply.new(messages: ['Booking dicatat.'], handoff: false, labels: ['booking'], trace: trace))

      expect { described_class.perform_now(message) }
        .to have_enqueued_job(Conversations::ActivityMessageJob)
        .with(conversation, hash_including(content: "#{ai_agent.name} added booking"))
      expect(conversation.reload.label_list).to eq(['booking'])
      expect(conversation).to be_pending
      expect(traces.sole).to have_attributes(status: 'replied', labels: ['booking'])
    end
  end

  it 'queues the sheet row the reply decided to write' do
    message = create(:message, **message_attributes, content: 'Nama Budi, booking 24 Oktober')
    allow(generator).to receive(:perform).and_return(
      AiAgents::ReplyGenerator::Reply.new(messages: ['Booking dicatat.'], handoff: false, labels: [], sheet_row: ['Budi', '', '24 Oktober'],
                                          trace: trace)
    )

    expect { described_class.perform_now(message) }
      .to have_enqueued_job(AiAgents::AppendSheetRowJob).with(conversation, ['Budi', '', '24 Oktober'])
    expect(AiAgents::ReplyGenerator).to have_received(:new).with(ai_agent: ai_agent, messages: anything, written_rows: [], bookings: [])
  end

  it 'records the booking the reply asked for' do
    ai_agent.update!(booking_enabled: true, booking_conditions: 'Saat customer ingin booking.',
                     booking_label_id: create(:label, account: account, title: 'booking').id)
    message = create(:message, **message_attributes, content: 'Ya, sudah benar')
    booking = { service: 'Cuci salon', customer_name: 'Budi', scheduled_at: Time.utc(2026, 11, 20, 3, 0), notes: nil, details: {} }
    allow(generator).to receive(:perform).and_return(
      AiAgents::ReplyGenerator::Reply.new(messages: ['Baik, kami teruskan ke staff.'], handoff: false, labels: [], booking: booking, trace: trace)
    )

    described_class.perform_now(message)

    expect(conversation.bookings.sole).to have_attributes(status: 'requested', service: 'Cuci salon', ai_agent: ai_agent)
    expect(conversation.reload.label_list).to eq(['booking'])
  end

  describe 'watcher' do
    let(:message) { create(:message, **message_attributes, content: 'Halo') }

    before { ai_agent.update!(watcher_enabled: true, transfer_conditions: 'Transfer when the customer complains.') }

    it 'is queued with the trace of the reply when it is enabled and the agent has actions' do
      described_class.perform_now(message)

      expect(AiAgents::WatchJob).to have_been_enqueued.with(conversation, traces.sole)
    end

    it 'is not queued when it is disabled, the agent has no actions, or the reply handed off' do
      ai_agent.update!(watcher_enabled: false)
      expect { described_class.perform_now(message) }.not_to have_enqueued_job(AiAgents::WatchJob)

      ai_agent.update!(watcher_enabled: true, transfer_conditions: '')
      expect { described_class.perform_now(create(:message, **message_attributes)) }.not_to have_enqueued_job(AiAgents::WatchJob)

      ai_agent.update!(transfer_conditions: 'Transfer when the customer complains.')
      allow(generator).to receive(:perform)
        .and_return(AiAgents::ReplyGenerator::Reply.new(messages: ['Baik.'], handoff: true, labels: [], trace: trace))
      expect { described_class.perform_now(create(:message, **message_attributes)) }.not_to have_enqueued_job(AiAgents::WatchJob)
    end

    it 'is queued for an agent whose only action is recording bookings, once its account has the bookings feature' do
      ai_agent.update!(transfer_conditions: '', booking_enabled: true, booking_conditions: 'Saat customer ingin booking.',
                       booking_label_id: create(:label, account: account).id)
      expect { described_class.perform_now(message) }.not_to have_enqueued_job(AiAgents::WatchJob)

      account.enable_features!('bookings')
      expect { described_class.perform_now(create(:message, **message_attributes)) }.to have_enqueued_job(AiAgents::WatchJob)
    end

    it 'is not queued after a reply of the scope check' do
      scope = AiAgents::ScopeGuard::Result.new(decision: 'OUT_OF_SCOPE', web_query: nil, web_search_status: nil, input_tokens: 900,
                                               output_tokens: 5, cached_input_tokens: nil, latency_ms: 700)
      scope_trace = AiAgents::ReplyGenerator::Trace.new(scope: scope, retrieval: nil, web_search: nil, validation: nil, invalid_outputs: [],
                                                        input_tokens: 900, output_tokens: 5, cached_input_tokens: nil, latency_ms: 700)
      allow(generator).to receive(:perform)
        .and_return(AiAgents::ReplyGenerator::Reply.new(messages: ['Maaf.'], handoff: false, labels: [], trace: scope_trace))

      expect { described_class.perform_now(message) }.not_to have_enqueued_job(AiAgents::WatchJob)
    end
  end

  context 'with the scope check of a strict agent' do
    let(:scope_decision) { 'OUT_OF_SCOPE' }
    let(:chat_requests) { [] }
    let(:message) { create(:message, **message_attributes, content: 'Siapa juara Piala Dunia terakhir?') }

    before do
      allow(AiAgents::ReplyGenerator).to receive(:new).and_call_original
      ai_agent.update!(scope_mode: 'strict', business_description: 'Toko roti di Bandung', allowed_topics: 'Produk, harga, dan pesanan',
                       off_topic_message: 'Maaf, Kak, saya hanya bisa membantu seputar toko.', clarification_message: 'Produk yang mana, Kak?',
                       knowledge_gap_message: 'Maaf, Kak, info itu belum tersedia.', watcher_enabled: true,
                       transfer_conditions: 'Alihkan bila pelanggan komplain.')
      create(:installation_config, name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'test-key')
      stub_request(:post, 'https://api.openai.com/v1/chat/completions').to_return do |request|
        chat_requests << JSON.parse(request.body)
        { status: 200, headers: { 'Content-Type' => 'application/json' },
          body: { id: 'chatcmpl-1', model: ai_agent.model, usage: { prompt_tokens: 900, completion_tokens: 5 },
                  choices: [{ message: { role: 'assistant', content: nil, tool_calls: [{ id: 'call_1', type: 'function', function: {
                    name: 'ai_agent_scope', arguments: { decision: scope_decision }.to_json
                  } }] } }] }.to_json }
      end
    end

    it 'sends the off-topic message as an AI reply that counts toward the message limit, and traces the decision' do
      expect { described_class.perform_now(message) }.not_to have_enqueued_job(AiAgents::WatchJob)

      expect(chat_requests.sole['tool_choice']).to eq('type' => 'function', 'function' => { 'name' => 'ai_agent_scope' })
      expect(ai_replies.outgoing.pluck(:content)).to eq(['Maaf, Kak, saya hanya bisa membantu seputar toko.'])
      expect(AiAgents::ConversationSession.new(conversation: conversation, ai_agent: ai_agent).reply_count).to eq(1)
      expect(conversation.reload).to be_pending
      expect(traces.sole).to have_attributes(status: 'replied', scope_decision: 'OUT_OF_SCOPE', scope_latency_ms: be >= 0, retrieval_mode: nil,
                                             retrieved: [], input_tokens: 900, output_tokens: 5, scope_input_tokens: 900, scope_output_tokens: 5,
                                             cached_input_tokens: nil, scope_policy_version: ai_agent.scope_policy_version)
    end

    context 'when the check returns no valid decision' do
      let(:scope_decision) { 'ALLOWED' }

      it 'hands the conversation off without replying' do
        described_class.perform_now(message)

        expect(ai_replies).to be_empty
        expect(handoff_activities.sole.additional_attributes).to eq('ai_agent_handoff' => 'error')
        expect(traces.sole).to have_attributes(status: 'error', error_class: 'AiAgents::LlmError', scope_decision: nil)
      end
    end
  end

  context 'with the reply check of a strict agent' do
    let(:message) { create(:message, **message_attributes, content: 'Saya mau komplain, harga detailing berapa sih?') }
    # One per call of the reply model, in order: the arguments of the reply function, or the text the model wrote instead.
    let(:reply_outputs) { [{ decision: 'answer', sources: [], messages: ['Detailing Rp500.000, kami sambungkan ke CS.'], handoff: true }] }

    before do
      allow(AiAgents::ReplyGenerator).to receive(:new).and_call_original
      ai_agent.update!(scope_mode: 'strict', business_description: 'Bengkel detailing mobil', allowed_topics: 'Layanan, harga, dan booking',
                       off_topic_message: 'Maaf, Kak.', clarification_message: 'Layanan yang mana, Kak?',
                       knowledge_gap_message: 'Maaf, Kak, info itu belum tersedia.', transfer_conditions: 'Alihkan bila pelanggan komplain.')
      create(:installation_config, name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'test-key')
      reply_calls = 0
      stub_request(:post, 'https://api.openai.com/v1/chat/completions').to_return do |request|
        name = JSON.parse(request.body)['tools'].sole['function']['name']
        output = name == 'ai_agent_reply' ? reply_outputs.fetch((reply_calls += 1) - 1) : { decision: 'IN_SCOPE' }
        message = if output.is_a?(String)
                    { role: 'assistant', content: output }
                  else
                    { role: 'assistant', content: nil,
                      tool_calls: [{ id: 'call_1', type: 'function', function: { name: name, arguments: output.to_json } }] }
                  end
        { status: 200, headers: { 'Content-Type' => 'application/json' },
          body: { id: 'chatcmpl-1', model: ai_agent.model, choices: [{ message: message }] }.to_json }
      end
    end

    it 'sends the knowledge gap message instead of an answer that cites no knowledge, still hands off, and traces why without content' do
      described_class.perform_now(message)

      expect(ai_replies.outgoing.pluck(:content)).to eq(['Maaf, Kak, info itu belum tersedia.'])
      expect(conversation.reload).to be_open
      expect(handoff_activities.sole.additional_attributes).to eq('ai_agent_handoff' => 'transfer_conditions')
      expect(traces.sole).to have_attributes(status: 'handoff', scope_decision: 'IN_SCOPE', reply_decision: 'answer', cited_ranks: [],
                                             blocked_reason: 'missing_sources', invalid_outputs: [])
      expect(traces.sole.attributes.to_json).not_to include('500.000', 'detailing', 'belum tersedia')
    end

    context 'when the model first writes text instead of the reply function' do
      let(:reply_outputs) do
        ['Detailing mulai Rp500.000, Kak.',
         { decision: 'conversational', sources: [], messages: ['Mohon maaf atas kendalanya, Kak. Kami sambungkan ke CS.'], handoff: true }]
      end

      it 'sends the reply of the second call and traces the shape of the first output without its content' do
        described_class.perform_now(message)

        expect(ai_replies.outgoing.pluck(:content)).to eq(['Mohon maaf atas kendalanya, Kak. Kami sambungkan ke CS.'])
        expect(traces.sole).to have_attributes(status: 'handoff', reply_decision: 'conversational', blocked_reason: nil, invalid_outputs: ['text'])
        expect(traces.sole.attributes.to_json).not_to include('500.000')
      end
    end
  end

  # Web widget and WhatsApp conversations are created with the first customer message, so the welcome comes after it.
  { channel_widget: {}, channel_whatsapp: { sync_templates: false, validate_provider_config: false } }.each do |channel, channel_options|
    context "when the welcome message follows the first question on #{channel}" do
      let(:inbox) { create(channel, account: account, **channel_options).inbox }
      let(:embedding) { Array.new(1536) { |index| index.zero? ? 1.0 : 0.0 } }
      let(:embedding_requests) { [] }
      let(:chat_requests) { [] }

      before do
        allow(AiAgents::ReplyGenerator).to receive(:new).and_call_original
        ai_agent.update!(welcome_message: 'Halo! Ada yang bisa kami bantu?')
        create(:installation_config, name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'test-key')
        create(:installation_config, name: 'AI_AGENT_EMBEDDING_MODEL', value: 'text-embedding-3-small')
        source = create(:ai_agent_knowledge_source, ai_agent: ai_agent)
        ai_agent.knowledge_chunks.create!(account: account, chunkable: source, chunkable_updated_at: source.updated_at,
                                          content: 'Jam buka toko: Senin sampai Sabtu 09.00-21.00', embedding: embedding,
                                          embedding_model: 'text-embedding-3-small')
        stub_request(:post, 'https://api.openai.com/v1/embeddings').to_return do |request|
          embedding_requests << JSON.parse(request.body)
          { status: 200, headers: { 'Content-Type' => 'application/json' },
            body: { data: [{ embedding: embedding }], usage: { prompt_tokens: 4 } }.to_json }
        end
        stub_request(:post, 'https://api.openai.com/v1/chat/completions').to_return do |request|
          chat_requests << JSON.parse(request.body)
          { status: 200, headers: { 'Content-Type' => 'application/json' },
            body: { id: 'chatcmpl-1', model: ai_agent.model, usage: { prompt_tokens: 10, completion_tokens: 5 },
                    choices: [{ message: { role: 'assistant', content: nil, tool_calls: [{ id: 'call_1', type: 'function', function: {
                      name: 'ai_agent_reply', arguments: { messages: ['Kami buka Senin sampai Sabtu, 09.00-21.00.'] }.to_json
                    } }] } }] }
              .to_json }
        end
      end

      it 'answers the question with the knowledge, after the greeting' do
        message = create(:message, **message_attributes, content: 'Halo, toko buka jam berapa?')
        AiAgentListener.instance.conversation_created(Events::Base.new('conversation.created', Time.zone.now, conversation: conversation))

        described_class.perform_now(message)

        expect(embedding_requests.sole['input']).to eq(['query: Halo, toko buka jam berapa?'])
        request = chat_requests.sole
        expect(request['messages'].first['content']).to include('<knowledge>', 'Jam buka toko: Senin sampai Sabtu 09.00-21.00')
        expect(request['messages'].drop(1).pluck('role', 'content'))
          .to eq([['assistant', 'Halo! Ada yang bisa kami bantu?'], ['user', 'Halo, toko buka jam berapa?']])
        expect(ai_replies.where("additional_attributes ->> 'ai_agent_reply_to' = ?", message.id.to_s).pluck(:content))
          .to eq(['Kami buka Senin sampai Sabtu, 09.00-21.00.'])
        expect(traces.sole).to have_attributes(status: 'replied', retrieval_mode: 'hybrid', input_tokens: 10, output_tokens: 5,
                                               latency_ms: be >= 0)
        expect(traces.sole.retrieved).to match([hash_including('chunk_id' => ai_agent.knowledge_chunks.sole.id, 'rank' => 1)])
      end
    end
  end

  context 'when Stop AI after Handoff is off' do
    let(:session) { AiAgents::ConversationSession.new(conversation: conversation, ai_agent: ai_agent) }

    before do
      ai_agent.update!(stop_ai_after_handoff: false, message_limit: 5)
      session.handoff!(:transfer_conditions)
    end

    it 'keeps answering after a handoff until a human agent replies' do
      described_class.perform_now(create(:message, **message_attributes, content: 'Masih ada pertanyaan'))
      expect(ai_replies.count).to eq(2)
      expect(conversation.reload.waiting_since).to be_present

      create(:message, **message_attributes, message_type: :outgoing, sender: create(:user, account: account), content: 'Saya bantu ya')
      described_class.perform_now(create(:message, **message_attributes, content: 'Terima kasih'))
      expect(ai_replies.count).to eq(2)
    end

    it 'stays quiet when Silent Agent Handoff is on' do
      ai_agent.update!(silent_handoff: true)

      described_class.perform_now(create(:message, **message_attributes, content: 'Masih ada pertanyaan'))

      expect(ai_replies).to be_empty
    end

    it 'stays quiet once the AI message limit is reached' do
      ai_agent.update!(message_limit: 1)
      session.reply!('Balasan', to: create(:message, **message_attributes))

      described_class.perform_now(create(:message, **message_attributes, content: 'Lagi'))

      expect(AiAgents::ReplyGenerator).not_to have_received(:new)
      expect(ai_replies.count).to eq(1)
    end
  end

  context 'with the request log on' do
    let(:message) { create(:message, **message_attributes, content: 'Kenapa mesin mobil overheat?') }
    let(:chat_requests) { [] }
    # One per call of the reply model, in order: the arguments of the reply function, the text the model wrote instead, or nil
    # for a request the model rejects.
    let(:reply_outputs) { [{ decision: 'answer', sources: [1, 2], messages: ['Dari internet: radiator tersumbat membuat mesin panas.'] }] }

    before do
      allow(AiAgents::ReplyGenerator).to receive(:new).and_call_original
      ai_agent.update!(scope_mode: 'strict', business_description: 'Bengkel mobil', allowed_topics: 'Servis dan info umum mobil',
                       off_topic_message: 'Maaf, di luar layanan kami.', clarification_message: 'Mobil yang mana, Kak?',
                       knowledge_gap_message: 'Maaf, info itu belum tersedia.', web_search_enabled: true, web_search_domains: 'otomotif.example',
                       context_limit: 1)
      vector = Array.new(1536) { |index| index.zero? ? 1.0 : 0.0 }
      source = create(:ai_agent_knowledge_source, ai_agent: ai_agent)
      ai_agent.knowledge_chunks.create!(account: account, chunkable: source, chunkable_updated_at: source.updated_at,
                                        content: 'Servis radiator Rp350.000', embedding: vector, embedding_model: 'text-embedding-3-small')
      { 'CAPTAIN_OPEN_AI_API_KEY' => 'sk-chat-secret', 'AI_AGENT_EMBEDDING_MODEL' => 'text-embedding-3-small',
        'AI_AGENT_EMBEDDING_API_KEY' => 'sk-embedding-secret', 'AI_AGENT_WEB_SEARCH_API_KEY' => 'exa-secret',
        'AI_AGENT_REQUEST_LOG_ENABLED' => 'true' }.each { |name, value| create(:installation_config, name: name, value: value) }
      cached = []
      Redis::Alfred.scan_each(match: 'ai_agents:web_search:*') { |key| cached << key }
      cached.each { |key| Redis::Alfred.delete(key) }
      stub_request(:post, 'https://api.openai.com/v1/embeddings').to_return(
        status: 200, headers: { 'Content-Type' => 'application/json' }, body: { data: [{ embedding: vector }] }.to_json
      )
      stub_request(:post, 'https://api.exa.ai/search').to_return(
        status: 200, headers: { 'Content-Type' => 'application/json' },
        body: { results: [{ title: 'Mesin overheat', url: 'https://otomotif.example/overheat', publishedDate: '2026-10-01T03:00:00.000Z',
                            highlights: ['Radiator tersumbat membuat mesin panas.'] }], costDollars: { total: 0.004 } }.to_json
      )
      reply_calls = 0
      stub_request(:post, 'https://api.openai.com/v1/chat/completions').to_return do |request|
        body = JSON.parse(request.body)
        chat_requests << body
        name = body['tools'].sole['function']['name']
        output = if name == 'ai_agent_reply'
                   reply_outputs.fetch((reply_calls += 1) - 1)
                 else
                   { decision: 'IN_SCOPE', web_query: 'penyebab mesin mobil overheat' }
                 end
        next { status: 400, headers: { 'Content-Type' => 'application/json' }, body: { error: { message: 'Bad request' } }.to_json } if output.nil?

        message = if output.is_a?(String)
                    { role: 'assistant', content: output }
                  else
                    { role: 'assistant', content: nil,
                      tool_calls: [{ id: 'call_1', type: 'function', function: { name: name, arguments: output.to_json } }] }
                  end
        { status: 200, headers: { 'Content-Type' => 'application/json' },
          body: { id: 'chatcmpl-1', model: ai_agent.model, choices: [{ message: message }],
                  usage: { prompt_tokens: 900, completion_tokens: 12, prompt_tokens_details: { cached_tokens: 256 } } }.to_json }
      end
    end

    it 'logs the reply with its steps in order, linked to its trace, conversation, and message' do
      described_class.perform_now(message)

      sent = "Dari internet: radiator tersumbat membuat mesin panas.\nhttps://otomotif.example/overheat"
      expect(ai_replies.pluck(:content)).to eq([sent])
      expect(AiAgent::RequestLog.sole).to have_attributes(
        source: 'reply', status: 'ok', account_id: account.id, ai_agent_id: ai_agent.id, conversation_id: conversation.id, message_id: message.id,
        reply_trace_id: traces.sole.id, latency_ms: be >= 0,
        input: { 'messages' => [{ 'role' => 'user', 'content' => 'Kenapa mesin mobil overheat?', 'attachments' => [] }] },
        output: { 'messages' => [sent], 'handoff' => false, 'labels' => [], 'sheet_row' => nil, 'booking' => nil }
      )
      steps = AiAgent::RequestLog.sole.steps
      expect(steps.pluck('step')).to eq(%w[scope_check embedding retrieval web_search reply reply_check])
      expect(steps.pluck('started_ms')).to eq(steps.pluck('started_ms').sort)
    end

    it 'logs what the scope check, the embedding, and the knowledge search sent and got' do
      described_class.perform_now(message)

      scope_check, embedding, retrieval = AiAgent::RequestLog.sole.steps
      expect(scope_check).to include('model' => ai_agent.model, 'tokens' => { 'input' => 644, 'output' => 12, 'cached_input' => 256 },
                                     'output' => { 'decision' => 'IN_SCOPE', 'web_query' => 'penyebab mesin mobil overheat' }, 'error_class' => nil)
      expect(scope_check['input']).to include('temperature' => 0, 'schema' => 'ai_agent_scope',
                                              'instructions' => chat_requests.first['messages'].first['content'])
      expect(embedding).to include('model' => 'text-embedding-3-small', 'output' => { 'vectors' => 1, 'dimensions' => 1536 },
                                   'input' => { 'input_type' => 'query', 'texts' => ['query: Kenapa mesin mobil overheat?'] })
      expect(retrieval['input']).to eq('mode' => 'hybrid', 'queries' => ['Kenapa mesin mobil overheat?'])
      expect(retrieval['output']['hits']).to match([include('rank' => 1, 'chunk_id' => ai_agent.knowledge_chunks.sole.id, 'score' => be > 0,
                                                            'chunkable_type' => 'AiAgent::KnowledgeSource', 'content' => 'Servis radiator Rp350.000',
                                                            'distance' => be_within(1e-6).of(0), 'neighbor_of' => nil)])
    end

    it 'logs what the web search, the reply model, and the reply check sent and got' do
      described_class.perform_now(message)

      web_search, reply, reply_check = AiAgent::RequestLog.sole.steps.last(3)
      expect(web_search['input']).to eq('provider' => 'exa', 'query' => 'penyebab mesin mobil overheat', 'domains' => ['otomotif.example'])
      expect(web_search['output']).to include('status' => 'searched', 'cost_usd' => 0.004, 'latency_ms' => be >= 0, 'results' => [
                                                { 'rank' => 1, 'title' => 'Mesin overheat', 'url' => 'https://otomotif.example/overheat',
                                                  'published_at' => '2026-10-01', 'text' => 'Radiator tersumbat membuat mesin panas.' }
                                              ])
      expect(reply).to include('model' => ai_agent.model, 'output' => reply_outputs.sole.deep_stringify_keys,
                               'tokens' => { 'input' => 644, 'output' => 12, 'cached_input' => 256 })
      expect(reply_check).to include('input' => { 'sources' => [1, 2] }, 'output' => { 'decision' => 'answer', 'blocked_reason' => nil })
    end

    it 'logs the instructions and messages of the reply step exactly as they went to the reply model' do
      described_class.perform_now(message)

      reply = AiAgent::RequestLog.sole.steps.find { |step| step['step'] == 'reply' }
      developer, *messages = chat_requests.last['messages']
      expect(reply['input']).to eq('temperature' => 0.5, 'instructions' => developer['content'], 'messages' => messages, 'schema' => 'ai_agent_reply')
      expect(reply['input']['instructions']).to include('<knowledge>', 'Servis radiator Rp350.000', '<web_results>')
    end

    it 'keeps no API key in the log' do
      described_class.perform_now(message)

      expect(AiAgent::RequestLog.sole.attributes.to_json)
        .not_to include('sk-chat-secret', 'sk-embedding-secret', 'exa-secret', 'Bearer', 'Authorization')
    end

    context 'when the reply model is asked again for a reply without a valid decision' do
      let(:reply_outputs) do
        ['Radiator tersumbat membuat mesin panas.',
         { decision: 'answer', sources: [2], messages: ['Dari internet: radiator tersumbat membuat mesin panas.'] }]
      end

      it 'logs both calls of the reply model with their checks' do
        described_class.perform_now(message)

        steps = AiAgent::RequestLog.sole.steps
        expect(steps.pluck('step')).to eq(%w[scope_check embedding retrieval web_search reply reply_check reply reply_check])
        expect(steps.select { |step| step['step'] == 'reply' }.pluck('output')).to eq(
          ['Radiator tersumbat membuat mesin panas.', reply_outputs.last.deep_stringify_keys]
        )
      end
    end

    context 'when the reply model fails' do
      let(:reply_outputs) { [nil] }

      it 'logs the error with the steps that ran, and still hands off with an error trace' do
        described_class.perform_now(message)

        expect(AiAgent::RequestLog.sole).to have_attributes(status: 'error', error_class: 'AiAgents::LlmError', message_id: message.id,
                                                            reply_trace_id: nil, output: {})
        expect(AiAgent::RequestLog.sole.steps.map { |step| step.slice('step', 'error_class') }.last(2)).to eq(
          [{ 'step' => 'web_search', 'error_class' => nil }, { 'step' => 'reply', 'error_class' => 'AiAgents::LlmError' }]
        )
        expect(handoff_activities.sole.additional_attributes).to eq('ai_agent_handoff' => 'error')
        expect(traces.sole).to have_attributes(status: 'error', error_class: 'AiAgents::LlmError')
      end
    end

    it 'sends the reply and keeps its trace when the log cannot be written' do
      error = ActiveRecord::StatementInvalid.new('PG::ConnectionBad')
      allow(AiAgent::RequestLog).to receive(:create!).and_raise(error)
      tracker = instance_double(ChatwootExceptionTracker, capture_exception: nil)
      allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)

      described_class.perform_now(message)

      expect(ai_replies.count).to eq(1)
      expect(handoff_activities).to be_empty
      expect(traces.sole).to have_attributes(status: 'replied', error_class: nil)
      expect(ChatwootExceptionTracker).to have_received(:new).with(error, account: account).once
    end

    it 'replies as before without a log with the request log off' do
      InstallationConfig.find_by(name: 'AI_AGENT_REQUEST_LOG_ENABLED').update!(value: 'false')

      described_class.perform_now(message)

      expect(ai_replies.count).to eq(1)
      expect(traces.sole).to have_attributes(status: 'replied', web_search_status: 'searched')
      expect(AiAgent::RequestLog.count).to eq(0)
    end
  end
end
