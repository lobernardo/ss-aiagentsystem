# RF-86: retry/dead-letter/error visibility for outbound Make integration
# requests that have kept failing past ScanSolo::MakeRequest's retry
# threshold, feeding the Execuções e auditoria screen. Scoped by account
# since every consuming endpoint is account-scoped (T02).
class ScanSolo::Make::DeadLetterQuery
  def self.call(account:)
    new(account: account).call
  end

  def initialize(account:)
    @account = account
  end

  def call
    ScanSolo::MakeRequest.where(account: account).dead_letter.order(created_at: :desc)
  end

  private

  attr_reader :account
end
