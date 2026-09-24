# RF-17/RF-82: reached only from ScanSolo::Proposal::CallbackHandler after a
# validated successful send result -- transitions the opportunity to
# `proposta_enviada` through ScanSolo::Pipeline::StageTransitionService
# (T12), whose stage-entry enrollment (RF-24) enrolls the post-proposal
# cadence, reusing its idempotency/terminal-stage guarantees rather than
# duplicating them (RF-19: a Ganho/Perdido opportunity is left untouched).
class ScanSolo::Proposal::SuccessHandler
  def self.call(proposal_version:)
    new(proposal_version: proposal_version).call
  end

  def initialize(proposal_version:)
    @proposal_version = proposal_version
  end

  def call
    opportunity = proposal_version.proposal.opportunity
    return if opportunity.ganho? || opportunity.perdido?

    transition_stage!(opportunity)
  end

  private

  attr_reader :proposal_version

  def transition_stage!(opportunity)
    return if opportunity.proposta_enviada?

    ScanSolo::Pipeline::StageTransitionService.new(opportunity: opportunity, target_stage: 'proposta_enviada').call
  end
end
