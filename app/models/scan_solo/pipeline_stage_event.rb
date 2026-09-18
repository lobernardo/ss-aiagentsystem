# == Schema Information
#
# Table name: scan_solo_pipeline_stage_events
#
#  id             :bigint           not null, primary key
#  actor_type     :string
#  from_stage     :string           not null
#  to_stage       :string           not null
#  created_at     :datetime         not null
#  actor_id       :bigint
#  opportunity_id :bigint           not null
#
# Indexes
#
#  idx_on_actor_type_actor_id_2f58bcdc3c                    (actor_type,actor_id)
#  index_scan_solo_pipeline_stage_events_on_opportunity_id  (opportunity_id)
#
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
