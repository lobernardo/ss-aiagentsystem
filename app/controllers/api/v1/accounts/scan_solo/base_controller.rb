class Api::V1::Accounts::ScanSolo::BaseController < Api::V1::Accounts::BaseController
  # Runs ahead of the entire inherited before_action chain (including
  # authentication), so a disabled account gets a 404 instead of revealing
  # that a ScanSolo endpoint exists behind auth.
  prepend_before_action :ensure_scansolo_enabled

  private

  def ensure_scansolo_enabled
    raise ActiveRecord::RecordNotFound unless Account.find(params[:account_id]).scansolo_enabled?
  end
end
