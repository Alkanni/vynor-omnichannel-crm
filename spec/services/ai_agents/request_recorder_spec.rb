require 'rails_helper'

RSpec.describe AiAgents::RequestRecorder do
  let(:ai_agent) { create(:ai_agent) }
  let(:logs) { AiAgent::RequestLog.where(ai_agent: ai_agent) }

  context 'with the request log off' do
    it 'runs the block and its steps without writing a log' do
      value = described_class.record(ai_agent: ai_agent, source: :playground, input: { messages: [] }) do |log|
        log.output = { messages: ['Halo'] }
        described_class.step(:reply, { instructions: 'Jawab.' }) do |step|
          step.output = 'Halo'
          'reply'
        end
      end

      expect(value).to eq('reply')
      expect(logs).to be_empty
    end
  end

  context 'with the request log on' do
    before { create(:installation_config, name: 'AI_AGENT_REQUEST_LOG_ENABLED', value: 'true') }

    it 'writes one log of the run with its steps in the order they ended, and returns what the block returns' do
      value = described_class.record(ai_agent: ai_agent, source: :playground, input: { messages: [{ role: :user, content: 'Jam buka?' }] }) do |log|
        described_class.step(:embedding, { input_type: :query, texts: ['query: Jam buka?'] }, model: 'text-embedding-3-small') do |step|
          step.output = { vectors: 1, dimensions: 1536 }
        end
        described_class.step(:reply, { instructions: 'Jawab.' }, model: 'gpt-4.1-mini') do |step|
          step.output = { 'messages' => ['Buka 08.00.'] }
          step.tokens = { input: 120, output: 10, cached_input: nil }
        end
        log.output = { messages: ['Buka 08.00.'] }
        :reply
      end

      expect(value).to eq(:reply)
      expect(logs.sole).to have_attributes(
        account_id: ai_agent.account_id, source: 'playground', status: 'ok', error_class: nil, latency_ms: be >= 0, conversation_id: nil,
        message_id: nil, reply_trace_id: nil, input: { 'messages' => [{ 'role' => 'user', 'content' => 'Jam buka?' }] },
        output: { 'messages' => ['Buka 08.00.'] }
      )
      expect(logs.sole.steps).to match([
                                         { 'step' => 'embedding', 'started_ms' => be >= 0, 'latency_ms' => be >= 0,
                                           'input' => { 'input_type' => 'query', 'texts' => ['query: Jam buka?'] },
                                           'output' => { 'vectors' => 1, 'dimensions' => 1536 }, 'model' => 'text-embedding-3-small',
                                           'tokens' => nil, 'error_class' => nil },
                                         { 'step' => 'reply', 'started_ms' => be >= 0, 'latency_ms' => be >= 0,
                                           'input' => { 'instructions' => 'Jawab.' }, 'output' => { 'messages' => ['Buka 08.00.'] },
                                           'model' => 'gpt-4.1-mini', 'tokens' => { 'input' => 120, 'output' => 10, 'cached_input' => nil },
                                           'error_class' => nil }
                                       ])
    end

    it 'keeps a run that raised as an error, with the steps that ran, and raises again' do
      expect do
        described_class.record(ai_agent: ai_agent, source: :reply, input: {}, conversation_id: 5, message_id: 9) do
          described_class.step(:scope_check, { instructions: 'Periksa.' }) { |step| step.output = { 'decision' => 'IN_SCOPE' } }
          described_class.step(:reply, { instructions: 'Jawab.' }) { raise AiAgents::LlmError, 'The AI model request failed (TimeoutError)' }
        end
      end.to raise_error(AiAgents::LlmError)

      expect(logs.sole).to have_attributes(status: 'error', error_class: 'AiAgents::LlmError', conversation_id: 5, message_id: 9, output: {})
      expect(logs.sole.steps.map { |step| step.slice('step', 'output', 'error_class') }).to eq(
        [{ 'step' => 'scope_check', 'output' => { 'decision' => 'IN_SCOPE' }, 'error_class' => nil },
         { 'step' => 'reply', 'output' => nil, 'error_class' => 'AiAgents::LlmError' }]
      )
      expect(logs.sole.attributes.values.join).not_to include('TimeoutError')
    end

    it 'links the run to the trace set while it runs' do
      trace = create(:ai_agent_reply_trace, ai_agent: ai_agent)

      described_class.record(ai_agent: ai_agent, source: :reply, input: {}) { |log| log.reply_trace_id = trace.id }

      expect(logs.sole.reply_trace).to eq(trace)
    end

    it 'records a step inside another step as part of it only' do
      described_class.record(ai_agent: ai_agent, source: :indexing, input: {}) do
        described_class.step(:embedding, { chunks: 2 }) do |step|
          described_class.step(:embedding, { texts: ['passage: Jam buka', 'passage: Harga'] }) { |inner| inner.output = { vectors: 2 } }
          step.output = { dimensions: 1536 }
        end
      end

      expect(logs.sole.steps.map { |step| step.slice('input', 'output') })
        .to eq([{ 'input' => { 'chunks' => 2 }, 'output' => { 'dimensions' => 1536 } }])
    end

    it 'only runs the block of a step outside a run' do
      expect(described_class.step(:reply, {}) { |step| step.output = 'Halo' }).to eq('Halo')
      expect(logs).to be_empty
    end

    it 'reports a log it cannot write without changing the outcome of the run' do
      error = ActiveRecord::StatementInvalid.new('PG::ConnectionBad')
      allow(AiAgent::RequestLog).to receive(:create!).and_raise(error)
      tracker = instance_double(ChatwootExceptionTracker, capture_exception: nil)
      allow(ChatwootExceptionTracker).to receive(:new).with(error, account: ai_agent.account).and_return(tracker)

      value = described_class.record(ai_agent: ai_agent, source: :playground, input: {}) { 'reply' }

      expect(value).to eq('reply')
      expect(tracker).to have_received(:capture_exception)
    end

    it 'keeps an image as a reference to its blob, without its content' do
      blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new('image bytes'), filename: 'aki.png', content_type: 'image/png')

      described_class.record(ai_agent: ai_agent, source: :reply, input: { messages: [{ role: :user, content: 'Ini?', attachments: [blob] }] }) do
        described_class.step(:reply, { messages: [{ role: :user, content: RubyLLM::Content.new('Ini?', [blob]) }] }) { nil }
      end

      reference = { 'blob_id' => blob.id, 'filename' => 'aki.png', 'content_type' => 'image/png', 'byte_size' => 11 }
      expect(logs.sole.input).to eq('messages' => [{ 'role' => 'user', 'content' => 'Ini?', 'attachments' => [reference] }])
      expect(logs.sole.steps.sole['input'])
        .to eq('messages' => [{ 'role' => 'user', 'content' => { 'text' => 'Ini?', 'attachments' => [reference] } }])
    end

    describe 'masking' do
      let(:text) { 'WA 0812-3456-7890 atau +62 813 1234 5678, +1 415 555 0100, email budi.s@mail.co.id. Harga Rp1.250.000, buka 08.00 - 17.00' }
      let(:masked) { 'WA [phone] atau [phone], [phone], email [email]. Harga Rp1.250.000, buka 08.00 - 17.00' }
      let(:mask_pii) { 'true' }

      before do
        create(:installation_config, name: 'AI_AGENT_REQUEST_LOG_MASK_PII', value: mask_pii)
        described_class.record(ai_agent: ai_agent, source: :playground, input: { messages: [{ role: :user, content: text }] }) do |log|
          described_class.step(:reply, { instructions: "Kontak: #{text}" }) { |step| step.output = { 'messages' => [text] } }
          log.output = { messages: [text], sheet_row: { 'Nomor HP' => '081234567890' } }
        end
      end

      it 'replaces phone numbers and e-mail addresses in every text with AI_AGENT_REQUEST_LOG_MASK_PII on' do
        expect(logs.sole.input).to eq('messages' => [{ 'role' => 'user', 'content' => masked }])
        expect(logs.sole.output).to eq('messages' => [masked], 'sheet_row' => { 'Nomor HP' => '[phone]' })
        expect(logs.sole.steps.sole.slice('input', 'output')).to eq('input' => { 'instructions' => "Kontak: #{masked}" },
                                                                    'output' => { 'messages' => [masked] })
      end

      context 'with AI_AGENT_REQUEST_LOG_MASK_PII off' do
        let(:mask_pii) { 'false' }

        it 'keeps the texts as they were' do
          expect(logs.sole.input).to eq('messages' => [{ 'role' => 'user', 'content' => text }])
          expect(logs.sole.output['sheet_row']).to eq('Nomor HP' => '081234567890')
        end
      end
    end
  end
end
