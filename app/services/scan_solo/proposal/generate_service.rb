# RF-73/RF-74/RF-75/RF-76: `proposal.generate` is the sole path that
# creates a ScanSolo::ProposalVersion. Rejects the request outright -- no
# record created -- when ScanSolo::Qualification::FieldResolver's proposal
# gate reports a required qualification field (satisfied = confirmado no
# estado do lead). With the qualification `concluida` only `faltante` fields
# block; while `em_andamento` any field not `confirmado` blocks (lead state
# RF-08; RF-74/RF-14).
# Requests generation exclusively through the registered provider (the mock
# provider outside production, RF-83) and never writes value/currency/
# artifact_url itself -- only ScanSolo::Proposal::CallbackHandler, invoked
# from a validated provider result, ever sets those fields (RF-76). Calling
# this alone never sends anything to the customer (RF-73).
# RF-24 / RF-25 / RNF-02: a version is only generated from a validated
# commercial reply -- the opportunity's `replied` quote request without a
# version yet; anything else is rejected with no record (422 at the API). The
# version keeps `quote_request_id` (unique index), and the check runs under
# the request lock, so concurrent calls create one version.
class ScanSolo::Proposal::GenerateService
  def self.call(opportunity:, quote_request:, correlation_id:, actor: nil, provider: nil)
    new(opportunity: opportunity, quote_request: quote_request, correlation_id: correlation_id, actor: actor, provider: provider).call
  end

  def initialize(opportunity:, quote_request:, correlation_id:, actor: nil, provider: nil)
    @opportunity = opportunity
    @quote_request = quote_request
    @correlation_id = correlation_id
    @actor = actor
    @provider = provider || ScanSolo::Proposal::Integration.provider!
  end

  def call
    version = ActiveRecord::Base.transaction do
      quote_request&.lock!
      reject_if_no_validated_reply!
      reject_if_incomplete!
      proposal = ScanSolo::Proposal.find_or_create_by!(opportunity: opportunity)
      proposal.versions.create!(generate_correlation_id: correlation_id, generate_requested_at: Time.current, quote_request: quote_request)
    end

    provider.request_generation(proposal_version: version, correlation_id: correlation_id, actor: actor)

    version.reload
  end

  private

  attr_reader :opportunity, :quote_request, :correlation_id, :actor, :provider

  def reject_if_no_validated_reply!
    return if quote_request&.opportunity_id == opportunity.id && quote_request.replied? &&
              !ScanSolo::ProposalVersion.exists?(quote_request_id: quote_request.id)

    reject!('sem resposta de orçamento validada')
  end

  def reject_if_incomplete!
    missing = missing_required_fields
    return if missing.empty?

    reject!("campos obrigatórios da proposta incompletos: #{missing.join(', ')}")
  end

  def reject!(message)
    version = ScanSolo::ProposalVersion.new
    version.errors.add(:base, message)
    raise ActiveRecord::RecordInvalid, version
  end

  def missing_required_fields
    config = ScanSolo::AiAgentConfig.published_for(opportunity.account)
    ScanSolo::Qualification::FieldResolver.call(opportunity: opportunity, config: config).proposal_gate_missing_labels
  end
end
