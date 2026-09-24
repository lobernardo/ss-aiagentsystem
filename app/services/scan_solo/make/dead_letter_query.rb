# RF-40: failed outbound Make requests that reached the retry threshold,
# feeding the Execuções dead-letter view. A request superseded by a later
# retry/reprocess of the same operation (same action and proposal version)
# is no longer a dead letter. Scoped by account since every consuming
# endpoint is account-scoped.
class ScanSolo::Make::DeadLetterQuery
  SUPERSEDED = <<~SQL.squish.freeze
    EXISTS (
      SELECT 1 FROM scan_solo_make_requests newer
      WHERE newer.account_id = scan_solo_make_requests.account_id
        AND newer.action = scan_solo_make_requests.action
        AND newer.payload->>'proposal_version_id' = scan_solo_make_requests.payload->>'proposal_version_id'
        AND newer.retry_count > scan_solo_make_requests.retry_count
    )
  SQL

  def self.call(account:)
    new(account: account).call
  end

  def initialize(account:)
    @account = account
  end

  def call
    ScanSolo::MakeRequest.where(account: account).dead_letter.where.not(SUPERSEDED).order(created_at: :desc)
  end

  private

  attr_reader :account
end
