# Bookings need the account's bookings feature. They follow their conversations: administrators reach all of the
# account's, other users those in their inboxes (see Conversations::PermissionFilterService).
class BookingPolicy < ApplicationPolicy
  def index?
    account.feature_enabled?('bookings')
  end

  def create?
    account.feature_enabled?('bookings')
  end

  def fields?
    account.feature_enabled?('bookings')
  end

  def update?
    account.feature_enabled?('bookings')
  end

  def history?
    account.feature_enabled?('bookings')
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.where(conversation_id: Conversations::PermissionFilterService.new(account.conversations, user, account).perform.select(:id))
    end
  end
end
