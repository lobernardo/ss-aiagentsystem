# RF-56 / CT-12: manual, audited and idempotent resend of the quote request,
# reusing ScanSolo::Quote::RequestService.
#
# 1. The published config must be valid; otherwise the RF-14 audit and
#    exception are recorded and the resend is refused.
# 2. Under the opportunity lock (shared with the request job): a `replied`
#    request is closed; an open one is reused with its thread and correlation
#    id; with no request, only the RF-14 case (still `concluida` with next
#    action `proposta` and a `quote_request.misconfigured` audit) creates the
#    single request (RF-15); anything else is not eligible.
# 3. After commit the CT-03 e-mail goes to the recipient published now; the
#    status does not change and the RF-53 notice is never repeated. One
#    `quote_request.resent` audit keeps the actor and recipient.
class ScanSolo::Quote::ResendService
  Result = Data.define(:quote_request, :recipient, :resent_at)

  def self.available?(opportunity)
    quote_request = opportunity.quote_request
    quote_request ? quote_request.open? : recoverable?(opportunity)
  end

  def self.recoverable?(opportunity)
    lead_state = opportunity.lead_state
    lead_state.concluida? && lead_state.next_action == 'proposta' &&
      ScanSolo::AuditEvent.exists?(subject: opportunity, event_type: ScanSolo::Quote::RequestService::MISCONFIGURED_EVENT)
  end

  def self.call(opportunity:, actor:)
    new(opportunity: opportunity, actor: actor).call
  end

  def initialize(opportunity:, actor:)
    @opportunity = opportunity
    @actor = actor
    @request_service = ScanSolo::Quote::RequestService.new
  end

  def call
    settings = resolve_settings!
    quote_request = ActiveRecord::Base.transaction do
      opportunity.lock!
      reusable_request || create_request!(settings)
    end

    request_service.deliver!(quote_request: quote_request, settings: settings)
    resent_at = Time.current
    ScanSolo::AuditLogger.record!(
      subject: opportunity, event_type: 'quote_request.resent', actor: actor, correlation_id: quote_request.correlation_id,
      payload: { quote_request_id: quote_request.id, recipient: settings.recipient, resent_at: resent_at.iso8601 }
    )
    Result.new(quote_request: quote_request, recipient: settings.recipient, resent_at: resent_at)
  end

  private

  attr_reader :opportunity, :actor, :request_service

  def resolve_settings!
    ScanSolo::Quote::Mailbox.resolve!(opportunity.account)
  rescue CustomExceptions::ScanSolo::QuoteInboxMisconfigured => e
    request_service.record_misconfigured!(opportunity, e)
    reject!('quote_inbox_misconfigured')
  end

  def reusable_request
    quote_request = ScanSolo::QuoteRequest.find_by(opportunity_id: opportunity.id)
    return if quote_request.nil?

    reject!('quote_request_closed') if quote_request.replied?
    quote_request
  end

  def create_request!(settings)
    reject!('quote_request_not_eligible') unless self.class.recoverable?(opportunity)

    request_service.create_request!(opportunity, settings)
  end

  def reject!(code)
    raise CustomExceptions::ScanSolo::QuoteRequestResendRejected, code
  end
end
