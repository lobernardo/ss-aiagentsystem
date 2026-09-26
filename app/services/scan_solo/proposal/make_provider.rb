# RF-37 / CT-05: the production proposal provider. Builds the Make payload
# (asyncapi `MakeIntegrationRequestPayload`) and delegates transport to
# ScanSolo::Make::OutboundRequestService, using the version's generate/send
# correlation id so the callback (CT-06) matches the version. `qualification`
# is the fixed canonical, present-only key set from
# ScanSolo::Qualification::FieldResolver#make_qualification (RF-15; CT-05 as
# refined in .spec/features/scansolo-agent-qualification-continuity/asyncapi.yaml).
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
    qualification = ScanSolo::Qualification::FieldResolver.call(contact: opportunity.contact, config: config).make_qualification

    ScanSolo::Make::OutboundRequestService.call(
      account: opportunity.account,
      action: action,
      correlation_id: correlation_id,
      idempotency_key: correlation_id,
      retry_count: retry_count,
      payload: {
        account_id: opportunity.account_id, opportunity_id: opportunity.id,
        proposal_version_id: proposal_version.id, qualification: qualification,
        requested_by_user_id: actor&.id, requested_at: Time.current.iso8601
      }
    )
  rescue ScanSolo::Make::OutboundRequestService::DeliveryError => e
    proposal_version.update!(status: :failed, failure_reason: e.reason)
    e.make_request
  end

  private_class_method :request
end
