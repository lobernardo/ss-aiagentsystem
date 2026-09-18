# RF-59: an opportunity's enrollment in one versioned cadence definition.
# Uniqueness on (opportunity_id, cadence_definition_id) is enforced by the
# DB index from the migration; this model-level validation gives a
# friendlier ActiveRecord::RecordInvalid instead of a raw RecordNotUnique
# for the common (non-racing) duplicate-enrollment path.
class ScanSolo::CadenceEnrollment < ApplicationRecord
  self.table_name = 'scan_solo_cadence_enrollments'

  belongs_to :opportunity, class_name: 'ScanSolo::PipelineOpportunity', foreign_key: :opportunity_id, inverse_of: :cadence_enrollments
  belongs_to :cadence_definition, class_name: 'ScanSolo::CadenceDefinition', foreign_key: :cadence_definition_id,
                                   inverse_of: :enrollments
  has_many :attempts, class_name: 'ScanSolo::CadenceAttempt', foreign_key: :enrollment_id, inverse_of: :enrollment, dependent: :destroy

  enum status: { active: 0, paused: 1, cancelled: 2, completed: 3 }

  validates :opportunity_id, uniqueness: { scope: :cadence_definition_id }
end
