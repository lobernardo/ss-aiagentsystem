# CT-07: administrator-only operational status (RF-60), sharing its checks
# with `scansolo:smoke` through ScanSolo::StatusReport. Credentials appear
# only as presence booleans (RNF-04).
class Api::V1::Accounts::ScanSolo::StatusController < Api::V1::Accounts::ScanSolo::BaseController
  def show
    authorize(Current.account, :show?, policy_class: ::ScanSolo::StatusPolicy)
    @report = ::ScanSolo::StatusReport.call(account: Current.account)
  end
end
