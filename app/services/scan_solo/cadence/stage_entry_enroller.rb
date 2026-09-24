# RF-24/RF-31: the single place that decides whether an opportunity entering a
# stage gets a cadence enrollment. Called after the stage is persisted by
# ScanSolo::Pipeline::OpportunityBootstrapService (novo_lead creation) and
# ScanSolo::Pipeline::StageTransitionService (every later entry), and by
# ScanSolo::Cadence::ResumeOnReturnService when return-to-AI finds no open
# enrollment. Opted-out contacts are never enrolled; a missing active
# definition is a deployment bug, so it is reported loudly instead of skipped.
class ScanSolo::Cadence::StageEntryEnroller
  STAGES = %w[novo_lead em_contato em_qualificacao proposta_enviada].freeze

  def self.call(opportunity:)
    new(opportunity: opportunity).call
  end

  def initialize(opportunity:)
    @opportunity = opportunity
  end

  def call
    return unless STAGES.include?(opportunity.stage)
    return if ScanSolo::ContactExtension.opted_out?(opportunity.contact)

    cadence_definition = ScanSolo::CadenceDefinition.current_for(opportunity.stage)
    return report_missing_definition! if cadence_definition.blank?

    ScanSolo::Cadence::EnrollmentService.call(opportunity: opportunity, cadence_definition: cadence_definition)
  end

  private

  attr_reader :opportunity

  def report_missing_definition!
    error = CustomExceptions::ScanSolo::CadenceDefinitionMissing.new("no active cadence definition for stage #{opportunity.stage}")
    ChatwootExceptionTracker.new(error, account: opportunity.account).capture_exception

    ScanSolo::AuditLogger.record!(
      subject: opportunity,
      event_type: 'cadence.definition_missing',
      correlation_id: SecureRandom.uuid,
      payload: { stage: opportunity.stage }
    )
    nil
  end
end
