# CT-12 / RF-56: manual resend of an opportunity's quote request.
class Api::V1::Accounts::ScanSolo::QuoteRequestsController < Api::V1::Accounts::ScanSolo::BaseController
  def resend
    authorize(::ScanSolo::QuoteRequest, :resend?)
    opportunity = ::ScanSolo::PipelineOpportunity.where(account_id: Current.account.id).find(params[:id])

    result = ::ScanSolo::Quote::ResendService.call(opportunity: opportunity, actor: Current.user)

    render json: {
      quote_request_id: result.quote_request.id, status: result.quote_request.status, correlation_id: result.quote_request.correlation_id,
      recipient: result.recipient, resent_at: result.resent_at
    }
  rescue CustomExceptions::ScanSolo::QuoteRequestResendRejected => e
    render json: { error: e.code }, status: :unprocessable_entity
  end
end
