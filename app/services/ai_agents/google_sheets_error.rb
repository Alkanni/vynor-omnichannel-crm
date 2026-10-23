# A Google Sheets request that failed; status is the Google HTTP status (nil when the token could not be refreshed).
class AiAgents::GoogleSheetsError < StandardError
  attr_reader :status

  def initialize(message, status: nil)
    super(message)
    @status = status
  end
end
