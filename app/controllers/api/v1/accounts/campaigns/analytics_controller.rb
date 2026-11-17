class Api::V1::Accounts::Campaigns::AnalyticsController < Api::V1::Accounts::BaseController
  RESULTS_PER_PAGE = 25

  before_action :set_campaign
  before_action :check_authorization

  def metrics
    recipients = @campaign.campaign_recipients
    @status_counts = recipients.group(:status).count
    # WhatsApp returned a message id: delivered and read messages, and those that failed after WhatsApp accepted them.
    @accepted_count = recipients.where.not(source_id: nil).count
  end

  def contacts
    return render_could_not_create_error("Invalid status: #{params[:status]}") if invalid_status_filter?

    recipients = @campaign.campaign_recipients.includes(:contact).order(:id)
    recipients = recipients.where(status: params[:status]) if params[:status].present?
    @recipients = recipients.page(params[:page] || 1).per(RESULTS_PER_PAGE)
  end

  private

  def set_campaign
    @campaign = Current.account.campaigns.find_by!(display_id: params[:campaign_id])
  end

  def check_authorization
    authorize(@campaign, :show?)
  end

  def invalid_status_filter?
    params[:status].present? && !CampaignRecipient.statuses.key?(params[:status])
  end
end
