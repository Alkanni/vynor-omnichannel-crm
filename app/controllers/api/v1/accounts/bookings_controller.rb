# The bookings staff see, confirm, record, and correct (#178, #196). A user reaches the bookings of the conversations they
# can open (see BookingPolicy); a booking or conversation outside them is not found. index takes `status` (one or
# several), `from` and `to` (ISO 8601 times; `to` excluded), `contact_id`, and `page`. create and fields take
# `conversation_id`, the conversation's display id. create and update take the booking fields (`service`,
# `customer_name`, `scheduled_at` as an ISO 8601 time, `notes`, and `details` as names and text); update with a `status`
# changes only the status, to the booking's own (which changes nothing) or one of its next statuses (see
# Booking::NEXT_STATUSES).
class Api::V1::Accounts::BookingsController < Api::V1::Accounts::BaseController
  RESULTS_PER_PAGE = 25

  before_action :check_authorization
  before_action :validate_filters, only: :index
  before_action :fetch_booking, only: :update
  before_action :fetch_conversation, only: [:create, :fields]
  before_action :validate_fields, only: [:create, :update]

  def index
    bookings = policy_scope(Current.account.bookings).includes(:contact, :conversation, :ai_agent).order(:scheduled_at, :id)
    bookings = bookings.where(status: @statuses) if @statuses.any?
    bookings = bookings.where(contact_id: params[:contact_id]) if params[:contact_id].present?
    bookings = bookings.where(scheduled_at: @from..) if @from
    bookings = bookings.where(scheduled_at: ...@to) if @to
    @bookings = bookings.page(params[:page] || 1).per(RESULTS_PER_PAGE)
  end

  # A booking the staff recorded themselves is confirmed already, so the customer gets no status message.
  def create
    @booking = Booking.transaction do
      @conversation.bookings.create!(account: Current.account, contact: @conversation.contact, ai_agent: @conversation.inbox.ai_agent,
                                     status: :confirmed, **@fields).tap { |booking| booking.record_creation!(Current.user) }
    end
    render :update, status: :created
  end

  # The fields the AI agent of the conversation's inbox asks for, which a booking recorded there also holds.
  def fields
    render json: { fields: Array(@conversation.inbox.ai_agent&.booking_fields) }
  end

  def update
    return edit_booking if params[:status].blank? && @fields.any?
    return render_could_not_create_error('Invalid status') unless Booking.statuses.key?(params[:status])
    unless params[:status] == @booking.status || @booking.next_statuses.include?(params[:status])
      return render_could_not_create_error("A #{@booking.status} booking cannot become #{params[:status]}")
    end

    @booking.change_status!(params[:status], Current.user)
  end

  private

  def edit_booking
    return render_could_not_create_error("A #{@booking.status} booking cannot be changed") if @booking.next_statuses.empty?

    @booking.edit!(@fields, Current.user)
  end

  def fetch_booking
    @booking = policy_scope(Current.account.bookings).find(params[:id])
  end

  def fetch_conversation
    @conversation = Conversations::PermissionFilterService.new(Current.account.conversations, Current.user, Current.account).perform
                                                          .find_by!(display_id: params[:conversation_id])
  end

  # The booking fields the request gives (see #valid_fields? and #normalized_fields).
  def validate_fields
    @fields = params.permit(:service, :customer_name, :scheduled_at, :notes).to_h.symbolize_keys
    @fields[:details] = params[:details].to_unsafe_h if params[:details].is_a?(ActionController::Parameters)
    return render_could_not_create_error('Invalid fields') unless valid_fields?

    @fields = normalized_fields
  rescue ArgumentError
    render_could_not_create_error('Invalid time')
  end

  # Every field is text, and the details are names with text.
  def valid_fields?
    return false if params.key?(:details) && !@fields.key?(:details)

    @fields.except(:details).values.all?(String) && @fields.fetch(:details, {}).all? { |name, text| name.present? && text.is_a?(String) }
  end

  # Stripped, with blank notes as none and the time parsed.
  def normalized_fields
    fields = @fields.transform_values { |value| value.is_a?(Hash) ? value.transform_values(&:strip) : value.strip }
    fields[:notes] = fields[:notes].presence if fields.key?(:notes)
    fields[:scheduled_at] = Time.iso8601(fields[:scheduled_at]) if fields[:scheduled_at].present?
    fields
  end

  def validate_filters
    @statuses = Array(params[:status]).compact_blank
    return render_could_not_create_error('Invalid status') unless @statuses.all? { |status| Booking.statuses.key?(status) }

    @from, @to = params.values_at(:from, :to).map { |time| Time.iso8601(time) if time.present? }
  rescue ArgumentError, TypeError
    render_could_not_create_error('Invalid time range')
  end
end
