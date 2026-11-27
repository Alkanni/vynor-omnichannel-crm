require 'rails_helper'

RSpec.describe 'Bookings API', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:other_inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:url) { "/api/v1/accounts/#{account.id}/bookings" }
  let!(:tomorrow) { create(:booking, account: account, conversation: conversation, scheduled_at: Time.utc(2026, 11, 20, 3, 0)) }
  let!(:later) do
    create(:booking, account: account, conversation: create(:conversation, account: account, inbox: other_inbox), status: :confirmed,
                     scheduled_at: Time.utc(2026, 11, 22, 3, 0), details: { 'Plat nomor' => 'B 1' })
  end

  before do
    account.enable_features!('bookings')
    create(:inbox_member, user: agent, inbox: inbox)
  end

  describe 'GET /api/v1/accounts/{account.id}/bookings' do
    it 'lists every booking of the account for an administrator, soonest first, with its contact, conversation, and agent' do
      get url, headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload'].pluck('id')).to eq([tomorrow.id, later.id])
      expect(response.parsed_body['payload'].last).to eq(
        'id' => later.id, 'status' => 'confirmed', 'next_statuses' => %w[cancelled completed no_show], 'rescheduled_from_id' => nil,
        'scheduled_at' => '2026-11-22T03:00:00Z', 'service' => 'Cuci salon',
        'customer_name' => 'Budi', 'notes' => nil, 'details' => { 'Plat nomor' => 'B 1' }, 'ai_agent' => nil,
        'contact' => { 'id' => later.contact.id, 'name' => later.contact.name, 'phone_number' => later.contact.phone_number },
        'conversation' => { 'id' => later.conversation.id, 'display_id' => later.conversation.display_id, 'inbox_id' => other_inbox.id },
        'created_at' => later.created_at.iso8601
      )
      expect(response.parsed_body['meta']).to eq('count' => 2, 'current_page' => 1)
    end

    it 'returns the AI agent that requested a booking and its notes' do
      ai_agent = create(:ai_agent, account: account, name: 'CS Bengkel')
      tomorrow.update!(ai_agent: ai_agent, notes: 'Bawa STNK')

      get url, headers: administrator.create_new_auth_token, as: :json

      expect(response.parsed_body['payload'].first).to include('ai_agent' => { 'id' => ai_agent.id, 'name' => 'CS Bengkel' }, 'notes' => 'Bawa STNK')
    end

    it 'returns 25 bookings per page with the total count' do
      create_list(:booking, 24, account: account, conversation: conversation, scheduled_at: Time.utc(2026, 11, 25, 3, 0))
      last = Booking.order(:id).last
      headers = administrator.create_new_auth_token

      get url, headers: headers, as: :json
      expect(response.parsed_body['payload'].size).to eq(25)
      expect(response.parsed_body['meta']).to eq('count' => 26, 'current_page' => 1)

      get url, params: { page: 2 }, headers: headers
      expect(response.parsed_body['payload'].pluck('id')).to eq([last.id])
      expect(response.parsed_body['meta']).to eq('count' => 26, 'current_page' => 2)
    end

    it 'lists only the bookings of the inboxes an agent is a member of' do
      get url, headers: agent.create_new_auth_token, as: :json

      expect(response.parsed_body['payload'].pluck('id')).to eq([tomorrow.id])
    end

    it 'filters by status, time range with the end left out, and contact' do
      headers = administrator.create_new_auth_token

      get url, params: { status: %w[confirmed cancelled] }, headers: headers
      expect(response.parsed_body['payload'].pluck('id')).to eq([later.id])
      get url, params: { from: '2026-11-21T00:00:00+07:00', to: '2026-11-23T00:00:00+07:00' }, headers: headers
      expect(response.parsed_body['payload'].pluck('id')).to eq([later.id])
      get url, params: { to: '2026-11-20T03:00:00Z' }, headers: headers
      expect(response.parsed_body['payload'].pluck('id')).to be_empty
      get url, params: { from: '2026-11-22T03:00:00Z' }, headers: headers
      expect(response.parsed_body['payload'].pluck('id')).to eq([later.id])
      get url, params: { status: ['', 'confirmed'] }, headers: headers
      expect(response.parsed_body['payload'].pluck('id')).to eq([later.id])
      get url, params: { contact_id: tomorrow.contact_id }, headers: headers
      expect(response.parsed_body['payload'].pluck('id')).to eq([tomorrow.id])
    end

    it 'returns unprocessable entity for an unknown status or a time that does not parse' do
      headers = administrator.create_new_auth_token

      get url, params: { status: 'done' }, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      get url, params: { from: 'besok' }, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      get url, params: { to: 'kemarin' }, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'returns unauthorized while the account lacks the bookings feature, and without a login' do
      account.disable_features!('bookings')

      get url, headers: administrator.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
      get url, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'lists a booking under the contact its contact was merged into' do
      base_contact = create(:contact, account: account)
      ContactMergeAction.new(account: account, base_contact: base_contact, mergee_contact: tomorrow.contact).perform
      headers = administrator.create_new_auth_token

      get url, headers: headers, as: :json
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload'].pluck('id')).to eq([tomorrow.id, later.id])

      get url, params: { contact_id: base_contact.id }, headers: headers
      expect(response.parsed_body['payload'].sole).to include('id' => tomorrow.id, 'contact' => a_hash_including('id' => base_contact.id))
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/bookings' do
    let(:ai_agent) do
      create(:ai_agent, account: account, booking_confirmed_message: 'Booking dikonfirmasi.', booking_services: ['Servis berkala'],
                        booking_fields: [{ 'name' => 'Plat nomor', 'description' => '', 'type' => 'text', 'options' => [], 'required' => true },
                                         { 'name' => 'Mobil', 'description' => '', 'type' => 'choice', 'options' => %w[Avanza Xenia],
                                           'required' => false }])
    end
    let(:fields) do
      { conversation_id: conversation.display_id, service: ' Poles body ', customer_name: 'Rina', scheduled_at: '2026-11-25T03:00:00Z',
        notes: ' ', details: { 'Plat nomor' => ' B 9 XY ' } }
    end

    before { create(:ai_agent_inbox, ai_agent: ai_agent, inbox: inbox) }

    it 'records a confirmed booking for the conversation, notes who recorded it, and does not message the customer' do
      post url, params: fields, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:created)
      booking = conversation.bookings.order(:id).last
      expect(booking).to have_attributes(status: 'confirmed', service: 'Poles body', customer_name: 'Rina', notes: nil,
                                         scheduled_at: Time.utc(2026, 11, 25, 3, 0), details: { 'Plat nomor' => 'B 9 XY' },
                                         contact: conversation.contact, ai_agent: ai_agent)
      expect(booking.audits.sole).to have_attributes(action: 'create', user: agent)
      expect(response.parsed_body).to include('id' => booking.id, 'status' => 'confirmed', 'next_statuses' => %w[cancelled completed no_show])
      expect(conversation.messages.activity.pluck(:content))
        .to include("#{agent.name} recorded booking ##{booking.id}: Poles body, 2026-11-25 10:00 WIB")
      expect(conversation.messages.outgoing).to be_empty
    end

    it 'accepts a time that has passed, for a visit recorded afterwards' do
      post url, params: fields.merge(scheduled_at: '2020-01-10T03:00:00Z'), headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:created)
    end

    it 'records a booking with a required field empty and values outside the services and options, which only guide the staff' do
      post url, params: fields.merge(details: { 'Plat nomor' => '', 'Mobil' => 'Innova' }), headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:created)
      expect(conversation.bookings.order(:id).last).to have_attributes(service: 'Poles body', details: { 'Plat nomor' => '', 'Mobil' => 'Innova' })
    end

    it 'refuses a booking without a service or a time, or with fields that are not text' do
      headers = agent.create_new_auth_token

      [{ service: ' ' }, { scheduled_at: '' }, { scheduled_at: 'besok' }, { service: 12 }, { details: 'B 9 XY' },
       { details: { 'Plat nomor' => 9 } }].each do |change|
        expect { post url, params: fields.merge(change), headers: headers, as: :json }.not_to change(Booking, :count)
        expect(response).to have_http_status(:unprocessable_entity), change.inspect
      end
    end

    it 'refuses a booking without a conversation, and does not find a conversation that does not exist' do
      headers = agent.create_new_auth_token

      expect { post url, params: fields.except(:conversation_id), headers: headers, as: :json }.not_to change(Booking, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('Missing conversation_id')

      post url, params: fields.merge(conversation_id: 999_999), headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it 'does not find a conversation outside the agent\'s inboxes, and needs the bookings feature' do
      other = create(:conversation, account: account, inbox: other_inbox)
      post url, params: fields.merge(conversation_id: other.display_id), headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)

      account.disable_features!('bookings')
      post url, params: fields, headers: administrator.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
      post url, params: fields, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/bookings/fields' do
    it 'returns the booking fields and services of the AI agent of the conversation\'s inbox, none without one' do
      headers = agent.create_new_auth_token
      get "#{url}/fields", params: { conversation_id: conversation.display_id }, headers: headers
      expect(response.parsed_body).to eq('fields' => [], 'services' => [])

      fields = [{ 'name' => 'Plat nomor', 'description' => 'Contoh: D 1234 ABC', 'type' => 'text', 'options' => [], 'required' => true },
                { 'name' => 'Mobil', 'description' => '', 'type' => 'choice', 'options' => %w[Avanza Xenia], 'required' => false }]
      ai_agent = create(:ai_agent, account: account, booking_fields: fields, booking_services: ['Servis berkala', 'Ganti oli'])
      create(:ai_agent_inbox, ai_agent: ai_agent, inbox: inbox)
      get "#{url}/fields", params: { conversation_id: conversation.display_id }, headers: headers
      expect(response.parsed_body).to eq('fields' => fields, 'services' => ['Servis berkala', 'Ganti oli'])

      outside = create(:conversation, account: account, inbox: other_inbox)
      get "#{url}/fields", params: { conversation_id: outside.display_id }, headers: headers
      expect(response).to have_http_status(:not_found)

      get "#{url}/fields", headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/bookings/:id' do
    it 'changes only the status and records who changed it in the conversation' do
      patch "#{url}/#{tomorrow.id}", params: { status: 'confirmed', service: 'Lain' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include('id' => tomorrow.id, 'status' => 'confirmed', 'next_statuses' => %w[cancelled completed no_show],
                                              'service' => 'Cuci salon')
      expect(tomorrow.reload).to have_attributes(status: 'confirmed', service: 'Cuci salon')
      expect(conversation.messages.activity.pluck(:content)).to include("#{agent.name} marked booking ##{tomorrow.id} as Confirmed")
    end

    it 'sends the customer the confirmed message of the booking\'s AI agent' do
      tomorrow.update!(ai_agent: create(:ai_agent, account: account, booking_confirmed_message: 'Booking {{booking.service}} dikonfirmasi.'))

      patch "#{url}/#{tomorrow.id}", params: { status: 'confirmed' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(conversation.messages.outgoing.pluck(:content)).to eq(['Booking Cuci salon dikonfirmasi.'])
    end

    it 'records nothing when the status stays the same' do
      headers = agent.create_new_auth_token

      expect { patch "#{url}/#{tomorrow.id}", params: { status: 'requested' }, headers: headers, as: :json }.not_to change(Message, :count)
      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include('id' => tomorrow.id, 'status' => 'requested')
    end

    it 'returns unprocessable entity for a status outside the list, or without a status or a field' do
      headers = agent.create_new_auth_token

      patch "#{url}/#{tomorrow.id}", params: { status: 'done' }, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      patch "#{url}/#{tomorrow.id}", params: { color: 'Lain' }, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(tomorrow.reload).to have_attributes(status: 'requested', service: 'Cuci salon')
    end

    it 'changes the fields of a booking, keeps its status, and notes each change without messaging the customer' do
      tomorrow.update!(status: :confirmed, ai_agent: create(:ai_agent, account: account, booking_confirmed_message: 'Booking dikonfirmasi.'),
                       details: { 'Plat nomor' => 'B 1' })
      headers = agent.create_new_auth_token

      patch "#{url}/#{tomorrow.id}", params: { service: 'Poles body', scheduled_at: '2026-11-20T07:00:00Z', notes: 'Bawa STNK',
                                               details: { 'Plat nomor' => 'B 2' } }, headers: headers, as: :json

      expect(response).to have_http_status(:success)
      expect(tomorrow.reload).to have_attributes(status: 'confirmed', service: 'Poles body', scheduled_at: Time.utc(2026, 11, 20, 7, 0),
                                                 notes: 'Bawa STNK', details: { 'Plat nomor' => 'B 2' })
      expect(conversation.messages.activity.pluck(:content).last)
        .to eq("#{agent.name} changed booking ##{tomorrow.id}: Service: Cuci salon → Poles body; Scheduled at: 2026-11-20 10:00 WIB → " \
               '2026-11-20 14:00 WIB; Notes: - → Bawa STNK; Details: Plat nomor B 1 → Plat nomor B 2')
      expect(conversation.messages.outgoing).to be_empty

      expect { patch "#{url}/#{tomorrow.id}", params: { service: ' Poles body ' }, headers: headers, as: :json }.not_to change(Message, :count)
      expect(response).to have_http_status(:success)
    end

    it 'does not change a cancelled booking, nor take fields that are not text' do
      headers = agent.create_new_auth_token

      patch "#{url}/#{tomorrow.id}", params: { service: 12 }, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)

      tomorrow.cancelled!
      patch "#{url}/#{tomorrow.id}", params: { service: 'Poles body' }, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('A cancelled booking cannot be changed')
      expect(tomorrow.reload.service).to eq('Cuci salon')
    end

    it 'makes every status change a booking may make' do
      headers = administrator.create_new_auth_token

      Booking::NEXT_STATUSES.each do |from, statuses|
        statuses.each do |status|
          tomorrow.update!(status: from)
          patch "#{url}/#{tomorrow.id}", params: { status: status }, headers: headers, as: :json

          expect(response).to have_http_status(:success), "#{from} to #{status}"
          expect(tomorrow.reload.status).to eq(status)
        end
      end
    end

    it 'refuses a status change the booking cannot make, and records nothing' do
      tomorrow.update!(status: :completed)
      headers = administrator.create_new_auth_token

      expect { patch "#{url}/#{tomorrow.id}", params: { status: 'requested' }, headers: headers, as: :json }.not_to change(Message, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('A completed booking cannot become requested')
      expect(tomorrow.reload).to be_completed
    end

    it 'keeps a rescheduled booking rescheduled, and lists it with the booking that replaces it' do
      tomorrow.rescheduled!
      replacement = create(:booking, account: account, conversation: conversation, rescheduled_from: tomorrow,
                                     scheduled_at: Time.utc(2026, 11, 21, 3, 0))
      headers = administrator.create_new_auth_token

      patch "#{url}/#{tomorrow.id}", params: { status: 'confirmed' }, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(tomorrow.reload).to be_rescheduled

      get url, params: { status: 'rescheduled' }, headers: headers
      expect(response.parsed_body['payload'].sole).to include('id' => tomorrow.id, 'next_statuses' => [], 'rescheduled_from_id' => nil)
      get url, params: { status: 'requested' }, headers: headers
      expect(response.parsed_body['payload'].sole).to include('id' => replacement.id, 'rescheduled_from_id' => tomorrow.id)
    end

    it 'keeps a cancelled booking cancelled, without messaging the customer' do
      tomorrow.update!(status: :cancelled, ai_agent: create(:ai_agent, account: account, booking_confirmed_message: 'Booking dikonfirmasi.'))
      headers = administrator.create_new_auth_token

      (Booking.statuses.keys - ['cancelled']).each do |status|
        patch "#{url}/#{tomorrow.id}", params: { status: status }, headers: headers, as: :json
        expect(response).to have_http_status(:unprocessable_entity), status
      end
      expect(tomorrow.reload).to be_cancelled
      expect(conversation.messages.where(message_type: %i[outgoing activity])).to be_empty
    end

    it 'does not find a booking outside the agent\'s inboxes or of another account' do
      patch "#{url}/#{later.id}", params: { status: 'cancelled' }, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)

      elsewhere = create(:booking)
      patch "#{url}/#{elsewhere.id}", params: { status: 'cancelled' }, headers: administrator.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
      expect([later.reload, elsewhere.reload]).to all(be_requested.or(be_confirmed))
    end

    it 'returns unauthorized while the account lacks the bookings feature' do
      account.disable_features!('bookings')

      patch "#{url}/#{tomorrow.id}", params: { status: 'confirmed' }, headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(tomorrow.reload).to be_requested
    end
  end

  # `later` holds a slot: it is confirmed, in an inbox the agent is not a member of, recorded by another AI agent.
  describe 'a slot a confirmed booking holds (#210)' do
    let(:slot_taken) do
      { 'message' => "Booking ##{later.id} is already confirmed for Ganti oli at 2026-11-22 10:00 WIB. Choose another time or service.",
        'error_code' => 'booking_slot_taken' }
    end
    let(:fields) do
      { conversation_id: conversation.display_id, service: 'ganti OLI', customer_name: 'Rina', scheduled_at: '2026-11-22T03:00:00Z' }
    end

    before { later.update!(service: 'Ganti oli', ai_agent: create(:ai_agent, account: account)) }

    it 'refuses a new booking at its time and service whatever the case, naming only that booking, and records nothing' do
      headers = agent.create_new_auth_token

      expect { post url, params: fields, headers: headers, as: :json }.not_to(change { [Booking.count, Message.count] })
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq(slot_taken)
    end

    it 'takes another service at that time, or that service at another time' do
      headers = agent.create_new_auth_token

      [{ service: 'Tune up' }, { scheduled_at: '2026-11-22T03:15:00Z' }].each do |change|
        post url, params: fields.merge(change), headers: headers, as: :json
        expect(response).to have_http_status(:created), change.inspect
      end
    end

    it 'leaves the slot free while that booking is not confirmed' do
      headers = administrator.create_new_auth_token

      %w[requested cancelled completed no_show rescheduled].each do |status|
        later.update!(status: status)
        post url, params: fields, headers: headers, as: :json

        expect(response).to have_http_status(:created), status
        Booking.find(response.parsed_body['id']).destroy!
      end
    end

    it 'refuses to move a confirmed booking into it, and still takes other changes or a requested booking' do
      tomorrow.update!(status: :confirmed)
      headers = administrator.create_new_auth_token

      expect do
        patch "#{url}/#{tomorrow.id}", params: { service: 'Ganti Oli', scheduled_at: '2026-11-22T03:00:00Z' }, headers: headers, as: :json
      end.not_to change(Message, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq(slot_taken)
      expect(tomorrow.reload).to have_attributes(service: 'Cuci salon', scheduled_at: Time.utc(2026, 11, 20, 3, 0))

      patch "#{url}/#{later.id}", params: { service: 'GANTI OLI', notes: 'Bawa STNK', details: { 'Plat nomor' => 'B 2' } }, headers: headers,
                                  as: :json
      expect(response).to have_http_status(:success)

      requested = create(:booking, account: account, conversation: conversation)
      patch "#{url}/#{requested.id}", params: { service: 'Ganti oli', scheduled_at: '2026-11-22T03:00:00Z' }, headers: headers, as: :json
      expect(response).to have_http_status(:success)
      expect(requested.reload).to have_attributes(status: 'requested', service: 'Ganti oli', scheduled_at: Time.utc(2026, 11, 22, 3, 0))
    end

    it 'refuses to confirm a requested booking in it without telling the customer, and still cancels that booking' do
      requested = create(:booking, account: account, conversation: conversation, service: 'Ganti oli', scheduled_at: Time.utc(2026, 11, 22, 3, 0),
                                   ai_agent: create(:ai_agent, account: account, booking_confirmed_message: 'Booking dikonfirmasi.'))
      headers = agent.create_new_auth_token

      expect { patch "#{url}/#{requested.id}", params: { status: 'confirmed' }, headers: headers, as: :json }.not_to change(Message, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq(slot_taken)
      expect(requested.reload).to be_requested

      patch "#{url}/#{requested.id}", params: { status: 'cancelled' }, headers: headers, as: :json
      expect(response).to have_http_status(:success)
      expect(requested.reload).to be_cancelled
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/bookings/:id/history (#225)' do
    let(:ai_agent) { create(:ai_agent, account: account, name: 'CS Bengkel') }
    let(:booking) do
      Booking.audit_as(ai_agent) do
        create(:booking, account: account, conversation: conversation, scheduled_at: Time.utc(2026, 11, 21, 3, 0),
                         details: { 'Plat nomor' => 'B 1' })
      end
    end

    it 'lists who recorded and changed the booking, oldest first, with each value before and after' do
      headers = agent.create_new_auth_token
      patch "#{url}/#{booking.id}", params: { service: 'Poles body', details: { 'Plat nomor' => 'B 2' } }, headers: headers, as: :json
      patch "#{url}/#{booking.id}", params: { status: 'confirmed' }, headers: headers, as: :json

      get "#{url}/#{booking.id}/history", headers: headers, as: :json

      expect(response).to have_http_status(:success)
      created, edited, confirmed = booking.audits.to_a
      staff = { 'type' => 'User', 'id' => agent.id, 'name' => agent.name }
      expect(response.parsed_body['payload']).to eq(
        [{ 'id' => created.id, 'action' => 'create', 'actor' => { 'type' => 'AiAgent', 'id' => ai_agent.id, 'name' => 'CS Bengkel' },
           'changes' => [{ 'field' => 'status', 'from' => nil, 'to' => 'requested' },
                         { 'field' => 'service', 'from' => nil, 'to' => 'Cuci salon' },
                         { 'field' => 'customer_name', 'from' => nil, 'to' => 'Budi' },
                         { 'field' => 'scheduled_at', 'from' => nil, 'to' => '2026-11-21T03:00:00.000Z' },
                         { 'field' => 'notes', 'from' => nil, 'to' => nil },
                         { 'field' => 'details', 'from' => nil, 'to' => { 'Plat nomor' => 'B 1' } }],
           'comment' => nil, 'created_at' => created.created_at.iso8601 },
         { 'id' => edited.id, 'action' => 'update', 'actor' => staff,
           'changes' => [{ 'field' => 'service', 'from' => 'Cuci salon', 'to' => 'Poles body' },
                         { 'field' => 'details', 'from' => { 'Plat nomor' => 'B 1' }, 'to' => { 'Plat nomor' => 'B 2' } }],
           'comment' => nil, 'created_at' => edited.created_at.iso8601 },
         { 'id' => confirmed.id, 'action' => 'update', 'actor' => staff,
           'changes' => [{ 'field' => 'status', 'from' => 'requested', 'to' => 'confirmed' }],
           'comment' => nil, 'created_at' => confirmed.created_at.iso8601 }]
      )
    end

    it 'names the user of an access token, no one for a change without a user, and no name once the user is deleted' do
      patch "#{url}/#{tomorrow.id}", params: { status: 'confirmed' }, headers: { api_access_token: agent.access_token.token }, as: :json
      expect(response).to have_http_status(:success)
      staff = { 'type' => 'User', 'id' => agent.id }

      get "#{url}/#{tomorrow.id}/history", headers: administrator.create_new_auth_token, as: :json
      expect(response.parsed_body['payload'].pluck('actor')).to eq([nil, staff.merge('name' => agent.name)])

      agent.destroy!
      get "#{url}/#{tomorrow.id}/history", headers: administrator.create_new_auth_token, as: :json
      expect(response.parsed_body['payload'].pluck('actor')).to eq([nil, staff.merge('name' => nil)])
    end

    it 'does not find a booking outside the conversations of the user, or of another account' do
      get "#{url}/#{later.id}/history", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)

      get "#{url}/#{create(:booking).id}/history", headers: administrator.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it 'returns unauthorized while the account lacks the bookings feature, and without a login' do
      account.disable_features!('bookings')

      get "#{url}/#{tomorrow.id}/history", headers: administrator.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
      get "#{url}/#{tomorrow.id}/history", as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
