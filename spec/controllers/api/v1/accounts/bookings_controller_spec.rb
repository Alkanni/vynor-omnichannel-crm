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

    it 'returns unprocessable entity for a status outside the list, or without a status' do
      headers = agent.create_new_auth_token

      patch "#{url}/#{tomorrow.id}", params: { status: 'done' }, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      patch "#{url}/#{tomorrow.id}", params: { service: 'Lain' }, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(tomorrow.reload).to have_attributes(status: 'requested', service: 'Cuci salon')
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
end
