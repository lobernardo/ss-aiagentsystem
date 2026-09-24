# RF-59/RF-30: the sole path that creates a ScanSolo::CadenceEnrollment.
# Idempotent per open (active/paused) enrollment of an (opportunity_id,
# cadence_definition_id) pair: a second call returns the open enrollment
# untouched, while a pair whose previous enrollments are all cancelled or
# completed gets a fresh one (re-enroll). The partial unique index on open
# enrollments is the backstop for a genuine race between two concurrent calls.
class ScanSolo::Cadence::EnrollmentService
  def self.call(opportunity:, cadence_definition:)
    new(opportunity: opportunity, cadence_definition: cadence_definition).call
  end

  def initialize(opportunity:, cadence_definition:)
    @opportunity = opportunity
    @cadence_definition = cadence_definition
  end

  def call
    open_enrollment || ScanSolo::CadenceEnrollment.transaction(requires_new: true) do
      enrollment = ScanSolo::CadenceEnrollment.create!(
        opportunity: opportunity, cadence_definition: cadence_definition, status: :active, current_step: 0
      )
      schedule_attempts!(enrollment)
      enrollment
    end
  rescue ActiveRecord::RecordNotUnique
    ScanSolo::CadenceEnrollment.open_for(opportunity, cadence_definition).first!
  end

  private

  attr_reader :opportunity, :cadence_definition

  def open_enrollment
    ScanSolo::CadenceEnrollment.open_for(opportunity, cadence_definition).first
  end

  def schedule_attempts!(enrollment)
    base_time = enrollment.created_at

    cadence_definition.offsets.each_with_index do |offset_hours, index|
      enrollment.attempts.create!(
        step: index + 1,
        cadence_version: cadence_definition.version,
        template_reference: cadence_definition.template_reference_for(index + 1),
        scheduled_at: base_time + offset_hours.hours
      )
    end

    enrollment.update!(next_attempt_at: enrollment.attempts.scheduled.order(:scheduled_at).first&.scheduled_at)
  end
end
