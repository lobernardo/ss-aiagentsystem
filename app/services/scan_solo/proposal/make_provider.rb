# RF-37 / CT-05: the production proposal provider. Builds the Make payload
# (asyncapi `MakeIntegrationRequestPayload`) and delegates transport to
# ScanSolo::Make::OutboundRequestService, using the version's generate/send
# correlation id so the callback (CT-06) matches the version. `qualification`
# is the fixed canonical, present-only key set from
# ScanSolo::Qualification::FieldResolver#make_qualification (RF-15; CT-05 as
# refined in .spec/features/scansolo-agent-qualification-continuity/asyncapi.yaml).
# CT-05 (RF-24, RF-26, RF-47) adds the version's `proposal_number` and the
# `commercial` data validated from the quote reply, with the deterministic
# `total_value_in_words` (never produced by AI). Versions created before the
# quote flow (legacy send/retry) have no quote request and carry no
# `commercial`.
# A transport failure never propagates: the version is marked `failed` with
# the mapped reason (`timeout`, `network_error`, `provider_unavailable`, ...)
# so an administrator can retry it (RF-40).
class ScanSolo::Proposal::MakeProvider
  def self.request_generation(proposal_version:, correlation_id:, actor: nil, retry_count: 0)
    request(proposal_version: proposal_version, correlation_id: correlation_id, action: 'proposal.generate', actor: actor,
            retry_count: retry_count)
  end

  def self.request_send(proposal_version:, correlation_id:, actor: nil, retry_count: 0, **)
    request(proposal_version: proposal_version, correlation_id: correlation_id, action: 'proposal.send', actor: actor,
            retry_count: retry_count)
  end

  def self.request(proposal_version:, correlation_id:, action:, actor:, retry_count:)
    opportunity = proposal_version.proposal.opportunity
    config = ScanSolo::AiAgentConfig.published_for(opportunity.account)
    qualification = ScanSolo::Qualification::FieldResolver.call(opportunity: opportunity, config: config).make_qualification

    payload = {
      account_id: opportunity.account_id, opportunity_id: opportunity.id,
      proposal_version_id: proposal_version.id, proposal_number: proposal_version.proposal_number, qualification: qualification,
      requested_by_user_id: actor&.id, requested_at: Time.current.iso8601
    }
    payload[:commercial] = commercial(proposal_version.quote_request) if proposal_version.quote_request

    ScanSolo::Make::OutboundRequestService.call(
      account: opportunity.account, action: action, correlation_id: correlation_id, idempotency_key: correlation_id,
      retry_count: retry_count, payload: payload
    )
  rescue ScanSolo::Make::OutboundRequestService::DeliveryError => e
    proposal_version.update!(status: :failed, failure_reason: e.reason)
    e.make_request
  end

  def self.commercial(quote_request)
    values = quote_request.commercial
    total_value = BigDecimal(values['total_value'].to_s)

    {
      total_value: total_value.to_f, total_value_in_words: ScanSolo::Quote::AmountInWords.call(total_value), currency: 'BRL',
      schedule: values['schedule'], scope: values['scope'], payment_terms: values['payment_terms'], notes: values['notes'].presence,
      quote_request_id: quote_request.id
    }.compact
  end

  private_class_method :request, :commercial
end
