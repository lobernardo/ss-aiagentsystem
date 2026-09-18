# RF-57: a versioned, configurable follow-up schedule per pipeline stage.
# `offsets` is a plain array of hour offsets from enrollment time -- a
# deterministic configuration value, never derived from a model call
# (RF-69). The template reference for each step is derived rather than
# stored, so fake/test references (RF-71) exist automatically without a
# separate templates table.
# == Schema Information
#
# Table name: scan_solo_cadence_definitions
#
#  id         :bigint           not null, primary key
#  active     :boolean          default(TRUE), not null
#  offsets    :jsonb            not null
#  stage      :string           not null
#  version    :integer          default(1), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_scan_solo_cadence_definitions_on_stage_and_version  (stage,version) UNIQUE
#
class ScanSolo::CadenceDefinition < ApplicationRecord
  self.table_name = 'scan_solo_cadence_definitions'

  has_many :enrollments,
           class_name: 'ScanSolo::CadenceEnrollment',
           foreign_key: :cadence_definition_id,
           inverse_of: :cadence_definition,
           dependent: :restrict_with_exception

  validates :stage, presence: true
  validates :version, presence: true, uniqueness: { scope: :stage }
  validates :offsets, presence: true

  scope :active, -> { where(active: true) }

  def self.current_for(stage)
    active.where(stage: stage.to_s).order(version: :desc).first
  end

  def attempt_count
    offsets.size
  end

  def offset_hours_for(step)
    offsets[step - 1]
  end

  def template_reference_for(step)
    "scansolo_cadence_#{stage}_v#{version}_step#{step}"
  end
end
