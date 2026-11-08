# CT-12 / RF-56: manual resend of an opportunity's quote request.
#
# CT-04 / RF-18: bulk "Marcar proposta enviada manualmente". Each id runs the
# service in `bulk` mode on its own, so one refusal never undoes the others;
# an id outside the account yields `not_found` in its item.
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

  def bulk_handled_manually
    authorize(::ScanSolo::QuoteRequest, :bulk_handled_manually?)
    ids = params[:opportunity_ids]
    return render(json: { error: 'invalid_opportunity_ids' }, status: :unprocessable_entity) unless ids.is_a?(Array) && ids.any? && ids.all?(Integer)

    opportunities = ::ScanSolo::PipelineOpportunity.where(account_id: Current.account.id, id: ids).index_by(&:id)
    results = ids.map do |id|
      { opportunity_id: id, result: bulk_result(opportunities[id]) }
    end

    render json: { results: results }
  end

  private

  def bulk_result(opportunity)
    return 'not_found' if opportunity.nil?

    ::ScanSolo::Quote::HandledManuallyService.call(opportunity: opportunity, actor: Current.user, mode: 'bulk')
    'handled'
  rescue CustomExceptions::ScanSolo::HandledManuallyRejected => e
    e.code
  end
end
