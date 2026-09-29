# RF-73/RF-74/RF-75/RF-76: `proposal.generate` is the sole path that
# creates a ScanSolo::ProposalVersion. Rejects the request outright -- no
# record created -- when ScanSolo::Qualification::FieldResolver reports any
# required qualification field unsatisfied, the same field-completeness rule
# ScanSolo::Cadence::ReplyCompletenessDetector uses for RF-16 (RF-74/RF-14).
# Requests generation exclusively through the registered provider (the mock
# provider outside production, RF-83) and never writes value/currency/
# artifact_url itself -- only ScanSolo::Proposal::CallbackHandler, invoked
# from a validated provider result, ever sets those fields (RF-76). Calling
# this alone never sends anything to the customer (RF-73).
class ScanSolo::Proposal::GenerateService
  def self.call(opportunity:, correlation_id:, actor: nil, provider: nil)
    new(opportunity: opportunity, correlation_id: correlation_id, actor: actor, provider: provider).call
  end

  def initialize(opportunity:, correlation_id:, actor: nil, provider: nil)
    @opportunity = opportunity
    @correlation_id = correlation_id
    @actor = actor
    @provider = provider || ScanSolo::Proposal::Integration.provider!
  end

  def call
    reject_if_incomplete!

    version = ActiveRecord::Base.transaction do
      proposal = ScanSolo::Proposal.find_or_create_by!(opportunity: opportunity)
      proposal.versions.create!(generate_correlation_id: correlation_id, generate_requested_at: Time.current)
    end

    provider.request_generation(proposal_version: version, correlation_id: correlation_id, actor: actor)

    version.reload
  end

  private

  attr_reader :opportunity, :correlation_id, :actor, :provider

  def reject_if_incomplete!
    missing = missing_required_fields
    return if missing.empty?

    version = ScanSolo::ProposalVersion.new
    version.errors.add(:base, "campos obrigatórios da proposta incompletos: #{missing.join(', ')}")
    raise ActiveRecord::RecordInvalid, version
  end

  def missing_required_fields
    config = ScanSolo::AiAgentConfig.published_for(opportunity.account)
    ScanSolo::Qualification::FieldResolver.call(opportunity: opportunity, config: config).proposal_gate_missing_labels
  end
end
