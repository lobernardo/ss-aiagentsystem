# RF-59: the sole path that creates a ScanSolo::CadenceEnrollment.
# Idempotent per (opportunity_id, cadence_definition_id): a second call with
# identical inputs returns the existing enrollment untouched rather than
# creating (or re-scheduling) a second one. The DB unique index from T45 is
# the backstop for a genuine race between two concurrent calls.
class ScanSolo::Cadence::EnrollmentService
  def self.call(opportunity:, cadence_definition:)
    new(opportunity: opportunity, cadence_definition: cadence_definition).call
  end

  def initialize(opportunity:, cadence_definition:)
    @opportunity = opportunity
    @cadence_definition = cadence_definition
  end

  def call
    ScanSolo::CadenceEnrollment.transaction(requires_new: true) do
      enrollment = ScanSolo::CadenceEnrollment.find_or_create_by!(
        opportunity: opportunity, cadence_definition: cadence_definition
      ) do |record|
        record.status = :active
        record.current_step = 0
      end

      schedule_attempts!(enrollment) if enrollment.attempts.empty?
      enrollment
    end
  rescue ActiveRecord::RecordNotUnique
    ScanSolo::CadenceEnrollment.find_by!(opportunity: opportunity, cadence_definition: cadence_definition)
  end

  private

  attr_reader :opportunity, :cadence_definition

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
