class Webhooks::TelegramController < ActionController::API
  before_action :set_channel

  def process_payload
    Webhooks::TelegramEventsJob.perform_later(params.to_unsafe_hash.except(:bot_token).merge(channel_id: @channel.id))

    callback_query = params[:callback_query]
    callback_query_id = callback_query[:id] if callback_query.respond_to?(:key?)
    return head :ok unless callback_query_id.is_a?(String) && callback_query_id.present?

    render json: { method: 'answerCallbackQuery', callback_query_id: callback_query_id }
  end

  private

  def set_channel
    @channel = params[:bot_token].present? ? legacy_channel : channel_from_secret
    head :unauthorized if @channel.blank?
  end

  def channel_from_secret
    secret = request.headers['X-Telegram-Bot-Api-Secret-Token']
    Channel::Telegram.find_by(webhook_secret: secret) if secret.present?
  end

  # Webhooks registered before webhook secrets existed post to /webhooks/telegram/:bot_token without the secret header.
  # They are accepted only until Migration::RegisterTelegramWebhooksJob re-registers the channel.
  def legacy_channel
    Channel::Telegram.find_by(bot_token: params[:bot_token], webhook_secret: nil)
  end
end
