class Api::V1::Accounts::ScanSolo::BaseController < Api::V1::Accounts::BaseController
  # Runs ahead of the entire inherited before_action chain (including
  # authentication), so a disabled account gets a 404 instead of revealing
  # that a ScanSolo endpoint exists behind auth.
  prepend_before_action :ensure_scansolo_enabled

  rescue_from CustomExceptions::ScanSolo::ProposalIntegrationNotConfigured do
    render json: { error: 'proposal_integration_not_configured' }, status: :unprocessable_entity
  end

  rescue_from CustomExceptions::ScanSolo::Forbidden do
    render json: { error: 'forbidden' }, status: :forbidden
  end

  private

  # RF-48: an authenticated account user denied by a ScanSolo policy gets 403,
  # not the native 401 that RequestExceptionHandler renders for Pundit.
  def authorize(...)
    super
  rescue Pundit::NotAuthorizedError
    raise CustomExceptions::ScanSolo::Forbidden
  end

  def ensure_scansolo_enabled
    raise ActiveRecord::RecordNotFound unless Account.find(params[:account_id]).scansolo_enabled?
  end
end
