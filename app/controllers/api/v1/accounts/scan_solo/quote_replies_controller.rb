# CT-08: pending quote replies (RF-19, RF-23) and their manual link (RF-20)
# or discard.
class Api::V1::Accounts::ScanSolo::QuoteRepliesController < Api::V1::Accounts::ScanSolo::BaseController
  before_action :set_quote_reply, only: [:link, :discard]

  rescue_from CustomExceptions::ScanSolo::QuoteReplyRejected do |e|
    render json: { error: e.code }, status: :unprocessable_entity
  end

  def index
    authorize(::ScanSolo::QuoteReply)
    return render json: { error: 'invalid_status' }, status: :unprocessable_entity unless params[:status] == 'pending'

    @quote_replies = ::ScanSolo::QuoteReply.pending.where(account_id: Current.account.id)
                                           .includes(:quote_request, message: [:sender, :conversation])
                                           .order(created_at: :desc, id: :desc)
  end

  def link
    authorize(@quote_reply)
    quote_request_id = params[:quote_request_id]
    return render json: { error: 'invalid_quote_request_id' }, status: :unprocessable_entity unless quote_request_id.is_a?(Integer)

    quote_request = ::ScanSolo::Quote::PendingReplyResolution.link!(
      quote_reply: @quote_reply, quote_request: ::ScanSolo::QuoteRequest.where(account_id: Current.account.id).find(quote_request_id),
      actor: Current.user
    )
    render json: { quote_request_id: quote_request.id, status: quote_request.status }
  end

  def discard
    authorize(@quote_reply)
    quote_reply = ::ScanSolo::Quote::PendingReplyResolution.discard!(quote_reply: @quote_reply, actor: Current.user)
    render json: { id: quote_reply.id, status: quote_reply.status }
  end

  private

  def set_quote_reply
    @quote_reply = ::ScanSolo::QuoteReply.where(account_id: Current.account.id).find(params[:id])
  end
end
