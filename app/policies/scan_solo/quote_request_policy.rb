# RF-56 / CT-12: only account administrators resend a quote request.
class ScanSolo::QuoteRequestPolicy < ScanSolo::ApplicationPolicy
  def resend?
    administrator?
  end
end
