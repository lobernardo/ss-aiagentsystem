# RF-65: deterministic field-completeness detection only -- reuses RF-16's
# "all required fields satisfied" rule as reported by
# ScanSolo::Qualification::FieldResolver (satisfied = confirmado no estado do
# lead; data only in the Contact does not count), never an NLP/intent
# classifier. A full reply (every required qualification field for the
# opportunity's stage now satisfied) stops/recalculates every pending
# cadence attempt. A partial reply changes nothing here: every reply already
# interrupted the immediate pending send through
# ScanSolo::Cadence::ReplyInterruptionService (RF-43).
class ScanSolo::Cadence::ReplyCompletenessDetector
  Result = Struct.new(:complete, :missing_fields, keyword_init: true) do
    def complete?
      complete
    end

    def partial?
      !complete
    end
  end

  def self.call(opportunity:)
    new(opportunity: opportunity).call
  end

  def initialize(opportunity:)
    @opportunity = opportunity
  end

  def call
    missing = missing_fields
    ScanSolo::Cadence::LifecycleService.cancel_all_for_opportunity!(opportunity) if missing.empty?

    Result.new(complete: missing.empty?, missing_fields: missing)
  end

  private

  attr_reader :opportunity

  def missing_fields
    config = ScanSolo::AiAgentConfig.published_for(opportunity.account)
    ScanSolo::Qualification::FieldResolver.call(opportunity: opportunity, config: config).missing_labels
  end
end
