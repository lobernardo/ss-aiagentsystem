# RF-17/RF-82: reached only from ScanSolo::Proposal::CallbackHandler after a
# validated successful send result -- transitions the opportunity to
# `proposta_enviada` through ScanSolo::Pipeline::StageTransitionService
# (T12) and enrolls it in the configured post-proposal cadence through
# ScanSolo::Cadence::EnrollmentService (T48), reusing both modules'
# existing idempotency/terminal-stage guarantees rather than duplicating
# them (RF-19: a Ganho/Perdido opportunity is left untouched).
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
    enroll_cadence!(opportunity)
  end

  private

  attr_reader :proposal_version

  def transition_stage!(opportunity)
    return if opportunity.proposta_enviada?

    ScanSolo::Pipeline::StageTransitionService.new(opportunity: opportunity, target_stage: 'proposta_enviada').call
  end

  def enroll_cadence!(opportunity)
    cadence_definition = ScanSolo::CadenceDefinition.current_for('proposta_enviada')
    return if cadence_definition.blank?

    ScanSolo::Cadence::EnrollmentService.call(opportunity: opportunity, cadence_definition: cadence_definition)
  end
end
