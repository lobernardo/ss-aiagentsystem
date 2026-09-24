class ScanSolo::Proposal::MakeProvider
  def self.request_generation(proposal_version:, correlation_id:)
    request(proposal_version: proposal_version, correlation_id: correlation_id, action: 'proposal.generate')
  end

  def self.request_send(proposal_version:, correlation_id:, **)
    request(proposal_version: proposal_version, correlation_id: correlation_id, action: 'proposal.send')
  end

  def self.request(proposal_version:, correlation_id:, action:)
    opportunity = proposal_version.proposal.opportunity
    config = ScanSolo::AiAgentConfig.published_for(opportunity.account)
    qualification = opportunity.contact.custom_attributes.slice(*Array(config&.required_qualification_fields))

    ScanSolo::Make::OutboundRequestService.call(
      account: opportunity.account,
      action: action,
      correlation_id: correlation_id,
      idempotency_key: correlation_id,
      payload: {
        account_id: opportunity.account_id, opportunity_id: opportunity.id,
        proposal_version_id: proposal_version.id, qualification: qualification
      }
    )
  end

  private_class_method :request
end
