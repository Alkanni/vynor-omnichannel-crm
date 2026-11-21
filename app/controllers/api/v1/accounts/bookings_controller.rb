# The bookings staff see and confirm (#178). A user reaches the bookings of the conversations they can open (see
# BookingPolicy); a booking outside them is not found. index takes `status` (one or several), `from` and `to` (ISO 8601
# times; `to` excluded), `contact_id`, and `page`; update takes only `status`, the booking's own (which changes nothing) or
# one of its next statuses (see Booking::NEXT_STATUSES).
class Api::V1::Accounts::BookingsController < Api::V1::Accounts::BaseController
  RESULTS_PER_PAGE = 25

  before_action :check_authorization
  before_action :validate_filters, only: :index
  before_action :fetch_booking, only: :update

  def index
    bookings = policy_scope(Current.account.bookings).includes(:contact, :conversation, :ai_agent).order(:scheduled_at, :id)
    bookings = bookings.where(status: @statuses) if @statuses.any?
    bookings = bookings.where(contact_id: params[:contact_id]) if params[:contact_id].present?
    bookings = bookings.where(scheduled_at: @from..) if @from
    bookings = bookings.where(scheduled_at: ...@to) if @to
    @bookings = bookings.page(params[:page] || 1).per(RESULTS_PER_PAGE)
  end

  def update
    return render_could_not_create_error('Invalid status') unless Booking.statuses.key?(params[:status])
    unless params[:status] == @booking.status || @booking.next_statuses.include?(params[:status])
      return render_could_not_create_error("A #{@booking.status} booking cannot become #{params[:status]}")
    end

    @booking.change_status!(params[:status], Current.user)
  end

  private

  def fetch_booking
    @booking = policy_scope(Current.account.bookings).find(params[:id])
  end

  def validate_filters
    @statuses = Array(params[:status]).compact_blank
    return render_could_not_create_error('Invalid status') unless @statuses.all? { |status| Booking.statuses.key?(status) }

    @from, @to = params.values_at(:from, :to).map { |time| Time.iso8601(time) if time.present? }
  rescue ArgumentError, TypeError
    render_could_not_create_error('Invalid time range')
  end
end
