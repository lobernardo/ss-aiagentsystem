class ScanSolo::PipelineStageEvent < ApplicationRecord
  self.table_name = 'scan_solo_pipeline_stage_events'

  belongs_to :opportunity,
             class_name: 'ScanSolo::PipelineOpportunity',
             inverse_of: :stage_events
  belongs_to :actor, polymorphic: true, optional: true

  validates :from_stage, presence: true, inclusion: { in: ScanSolo::PipelineOpportunity.stages.keys }
  validates :to_stage, presence: true, inclusion: { in: ScanSolo::PipelineOpportunity.stages.keys }

  def readonly?
    persisted?
  end
end
