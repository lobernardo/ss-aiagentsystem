# RF-56 / CT-12: only account administrators resend a quote request.
class ScanSolo::QuoteRequestPolicy < ScanSolo::ApplicationPolicy
  def resend?
    administrator?
  end

  # CT-04 / RF-18: any member of the account runs the bulk manual action.
  def bulk_handled_manually?
    account_user.present?
  end
end
