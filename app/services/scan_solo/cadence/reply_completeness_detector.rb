# RF-65: deterministic field-completeness detection only -- reuses RF-16's
# "all required fields satisfied" rule (the same
# `custom_attributes[field].present?` check as
# ScanSolo::Actions::QualificationFieldAction), never an NLP/intent
# classifier. A full reply (every required qualification field for the
# opportunity's stage now satisfied) stops/recalculates every pending
# cadence attempt; a partial reply cancels only the immediate pending send,
# leaving the remaining schedule untouched.
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

    if missing.empty?
      ScanSolo::Cadence::LifecycleService.cancel_all_for_opportunity!(opportunity)
    else
      cancel_immediate_pending!
    end

    Result.new(complete: missing.empty?, missing_fields: missing)
  end

  private

  attr_reader :opportunity

  def required_fields
    Array(ScanSolo::AiAgentConfig.published_for(opportunity.account)&.required_qualification_fields)
  end

  def missing_fields
    contact = opportunity.contact
    return required_fields if contact.blank?

    required_fields.select { |field| contact.custom_attributes[field].blank? }
  end

  def cancel_immediate_pending!
    opportunity.cadence_enrollments.active.find_each do |enrollment|
      next_attempt = enrollment.attempts.scheduled.order(:scheduled_at).first
      next if next_attempt.blank?

      ScanSolo::Cadence::AttemptEvidenceRecorder.record_cancelled!(next_attempt)
    end
  end
end
