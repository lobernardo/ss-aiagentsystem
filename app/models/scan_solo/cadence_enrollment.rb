# Only active/paused enrollments reserve an opportunity and cadence definition pair.
# == Schema Information
#
# Table name: scan_solo_cadence_enrollments
#
#  id                    :bigint           not null, primary key
#  current_step          :integer          default(0), not null
#  next_attempt_at       :datetime
#  paused_at             :datetime
#  status                :integer          default("active"), not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  cadence_definition_id :bigint           not null
#  opportunity_id        :bigint           not null
#
# Indexes
#
#  idx_scansolo_cadence_enrollments_on_opportunity_and_definition  (opportunity_id,cadence_definition_id) UNIQUE
#  index_scan_solo_cadence_enrollments_on_cadence_definition_id    (cadence_definition_id)
#  index_scan_solo_cadence_enrollments_on_opportunity_id           (opportunity_id)
#
# Foreign Keys
#
#  fk_rails_...  (cadence_definition_id => scan_solo_cadence_definitions.id)
#  fk_rails_...  (opportunity_id => scan_solo_pipeline_opportunities.id)
#
class ScanSolo::CadenceEnrollment < ApplicationRecord
  self.table_name = 'scan_solo_cadence_enrollments'

  belongs_to :opportunity, class_name: 'ScanSolo::PipelineOpportunity', inverse_of: :cadence_enrollments
  belongs_to :cadence_definition, class_name: 'ScanSolo::CadenceDefinition',
                                  inverse_of: :enrollments
  has_many :attempts, class_name: 'ScanSolo::CadenceAttempt', foreign_key: :enrollment_id, inverse_of: :enrollment, dependent: :destroy

  enum status: { active: 0, paused: 1, cancelled: 2, completed: 3 }

  scope :open_for, lambda { |opportunity, cadence_definition|
    where(opportunity: opportunity, cadence_definition: cadence_definition, status: %i[active paused])
  }

  validates :opportunity_id, uniqueness: {
    scope: :cadence_definition_id, conditions: -> { where(status: %i[active paused]) }
  }, if: -> { active? || paused? }
end
