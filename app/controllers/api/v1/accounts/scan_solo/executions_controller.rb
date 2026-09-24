# RF-61 / CT-10: read-only Execuções feed; every query lives in
# ScanSolo::ExecutionsFeedQuery.
class Api::V1::Accounts::ScanSolo::ExecutionsController < Api::V1::Accounts::ScanSolo::BaseController
  def index
    authorize(Current.account, :index?, policy_class: ::ScanSolo::ExecutionPolicy)

    @feed = ::ScanSolo::ExecutionsFeedQuery.call(account: Current.account)
  end
end
