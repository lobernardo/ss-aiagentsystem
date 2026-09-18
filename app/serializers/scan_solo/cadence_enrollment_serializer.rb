# RF-63: exposes current step and next-attempt time per cadence enrollment,
# matching the CadenceEnrollment schema in the CT-06 OpenAPI contract
# exactly -- consumed both by the cadence_enrollments controller (T56) and
# by the pipeline_opportunities serialization of `next_follow_up_at`.
class ScanSolo::CadenceEnrollmentSerializer
  def initialize(enrollment)
    @enrollment = enrollment
  end

  def as_json(*)
    {
      id: enrollment.id,
      opportunity_id: enrollment.opportunity_id,
      cadence_definition_id: enrollment.cadence_definition_id,
      status: enrollment.status,
      current_step: enrollment.current_step,
      next_attempt_at: enrollment.next_attempt_at
    }
  end

  private

  attr_reader :enrollment
end
