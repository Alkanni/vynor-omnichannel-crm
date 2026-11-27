require 'rails_helper'

RSpec.describe AiAgents::BookingSummary do
  let(:account) { create(:account) }
  let(:ai_agent) do
    create(:ai_agent, account: account, timezone: 'Asia/Jakarta', booking_enabled: true, booking_conditions: 'Saat customer ingin datang.',
                      booking_label_id: create(:label, account: account).id,
                      booking_fields: [{ 'name' => 'Plat nomor', 'description' => '', 'type' => 'text', 'options' => [], 'required' => true },
                                       { 'name' => 'Mobil', 'description' => '', 'type' => 'text', 'options' => [], 'required' => false }],
                      booking_summary_template: "Ringkasan\nNama: {{booking.customer_name}}\nLayanan: {{booking.service}}\n" \
                                                "Tanggal: {{booking.date}} {{booking.time}}\n{{booking.extra_fields}}\nCatatan: {{booking.notes}}")
  end
  let(:conversation) { create(:conversation, account: account, contact: create(:contact, account: account, name: 'Budi Santoso')) }
  let(:summary) do
    described_class.new(ai_agent: ai_agent, conversation: conversation, actions: AiAgents::ActionSchema.new(ai_agent: ai_agent, reply: true))
  end
  let(:trace) do
    AiAgents::ReplyGenerator::Trace.new(scope: nil, retrieval: nil, web_search: nil, validation: nil, invalid_outputs: [], input_tokens: nil,
                                        output_tokens: nil, cached_input_tokens: nil, latency_ms: 10)
  end
  let(:reply) { AiAgents::ReplyGenerator::Reply.new(messages: ['Baik, Kak.'], handoff: false, labels: [], trace: trace) }
  let(:booking) do
    { 'customer_name' => '', 'service' => 'Cuci salon', 'date' => '2026-11-20', 'time' => '13:00', 'notes' => 'Bawa STNK',
      'Plat nomor' => 'B 1234 CD', 'Mobil' => '' }
  end

  before do
    account.enable_features!('bookings')
    travel_to(Time.utc(2026, 11, 19, 3, 0))
  end

  it 'ends the reply with the summary rendered from the template, with the contact name for a blank name and only the filled fields' do
    text = "Ringkasan\nNama: Budi Santoso\nLayanan: Cuci salon\nTanggal: 20/11/2026 13:00\nPlat nomor: B 1234 CD\nCatatan: Bawa STNK"

    expect(summary.add_to(reply, 'show_booking_summary' => true, 'booking' => booking))
      .to have_attributes(messages: ['Baik, Kak.', text], booking_summary: text, booking_summary_rejection: nil)
  end

  it 'keeps the summary as the last of the bubbles a reply may have' do
    reply = self.reply.with(messages: %w[Satu Dua Tiga Empat Lima])

    expect(summary.add_to(reply, 'show_booking_summary' => true, 'booking' => booking).messages)
      .to match(['Satu', 'Dua', 'Tiga', 'Empat', start_with('Ringkasan')])
  end

  it 'renders a summary in the playground with the name the model gave and none of the conversation variables' do
    ai_agent.update!(booking_summary_template: 'Booking {{booking.service}} atas nama {{booking.customer_name}}{{contact.name}}.')
    summary = described_class.new(ai_agent: ai_agent, conversation: nil, actions: AiAgents::ActionSchema.new(ai_agent: ai_agent, reply: true))

    expect(summary.add_to(reply, 'show_booking_summary' => true, 'booking' => booking.merge('customer_name' => 'Budi')).messages.last)
      .to eq('Booking Cuci salon atas nama Budi.')
  end

  it 'leaves the bubbles of the model as they are and says why a booking that cannot be one has no summary' do
    {
      { 'time' => 'jam 1 siang' } => :invalid_schedule, { 'date' => '2026-11-18' } => :past_schedule, { 'service' => ' ' } => :missing_service,
      { 'Plat nomor' => ' ' } => :missing_required_field
    }.each do |change, reason|
      expect(summary.add_to(reply, 'show_booking_summary' => true, 'booking' => booking.merge(change)))
        .to have_attributes(messages: ['Baik, Kak.'], booking_summary: nil, booking_summary_rejection: reason), change.inspect
    end
  end

  it 'shows no summary when the reply shows none, records the booking already, hands off, or failed the check' do
    gap = AiAgents::ReplyValidator::Result.new(decision: 'clarify', sources: [], blocked_reason: 'unsupported_number')
    [
      [reply, { 'show_booking_summary' => false }], [reply, { 'show_booking_summary' => true, 'create_booking' => true }],
      [reply.with(handoff: true), { 'show_booking_summary' => true }],
      [reply.with(trace: trace.with(validation: gap)), { 'show_booking_summary' => true }]
    ].each do |given, flags|
      expect(summary.add_to(given, flags.merge('booking' => booking)))
        .to have_attributes(messages: given.messages, booking_summary: nil, booking_summary_rejection: nil), flags.inspect
    end
  end
end
