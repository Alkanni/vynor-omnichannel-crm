require 'rails_helper'

RSpec.describe 'Webhooks::TelegramController', type: :request do
  let!(:telegram_channel) { create(:channel_telegram, webhook_secret: 'webhook-secret') }
  let(:headers) { { 'X-Telegram-Bot-Api-Secret-Token' => 'webhook-secret' } }

  before do
    allow(Webhooks::TelegramEventsJob).to receive(:perform_later)
  end

  describe 'POST /webhooks/telegram' do
    it 'calls the telegram events job with the channel id and without the bot token' do
      post '/webhooks/telegram', params: { update_id: 123, message: { text: 'hello' } }, headers: headers, as: :json

      expect(response).to have_http_status(:success)
      expect(response.body).to be_empty
      expect(Webhooks::TelegramEventsJob).to have_received(:perform_later).with(
        hash_including('channel_id' => telegram_channel.id, 'telegram' => hash_including('update_id' => 123))
      ).once
    end

    it 'acknowledges callback queries in the webhook response' do
      post '/webhooks/telegram', params: {
        update_id: 123,
        callback_query: { id: 'callback-query-id', data: 'Option 1' }
      }, headers: headers, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to eq(
        'method' => 'answerCallbackQuery',
        'callback_query_id' => 'callback-query-id'
      )
      expect(Webhooks::TelegramEventsJob).to have_received(:perform_later).with(
        hash_including('telegram' => hash_including('callback_query' => hash_including('id' => 'callback-query-id')))
      ).once
    end

    it 'returns an empty response for a malformed callback query' do
      post '/webhooks/telegram', params: { update_id: 123, callback_query: 'invalid' }, headers: headers, as: :json

      expect(response).to have_http_status(:success)
      expect(response.body).to be_empty
      expect(Webhooks::TelegramEventsJob).to have_received(:perform_later).once
    end

    it 'returns unauthorized without the secret header' do
      post '/webhooks/telegram', params: { update_id: 123 }, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(Webhooks::TelegramEventsJob).not_to have_received(:perform_later)
    end

    it 'returns unauthorized for an unknown secret' do
      post '/webhooks/telegram', params: { update_id: 123 }, headers: { 'X-Telegram-Bot-Api-Secret-Token' => 'wrong' }, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(Webhooks::TelegramEventsJob).not_to have_received(:perform_later)
    end
  end

  describe 'POST /webhooks/telegram/{:bot_token}' do
    it 'calls the telegram events job for a channel without a webhook secret' do
      legacy_channel = create(:channel_telegram, bot_token: 'legacy_bot_token')

      post '/webhooks/telegram/legacy_bot_token', params: { update_id: 123 }, as: :json

      expect(response).to have_http_status(:success)
      expect(Webhooks::TelegramEventsJob).to have_received(:perform_later).once do |job_params|
        expect(job_params).to include('channel_id' => legacy_channel.id)
        expect(job_params).not_to have_key('bot_token')
      end
    end

    it 'returns unauthorized once the channel has a webhook secret' do
      post "/webhooks/telegram/#{telegram_channel.bot_token}", params: { update_id: 123 }, headers: headers, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(Webhooks::TelegramEventsJob).not_to have_received(:perform_later)
    end

    it 'returns unauthorized for an unknown bot token' do
      post '/webhooks/telegram/random_bot_token', params: { update_id: 123 }, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(Webhooks::TelegramEventsJob).not_to have_received(:perform_later)
    end
  end
end
