# RF-77: aggregates every ScanSolo::ProposalVersion generated for a single
# ScanSolo::PipelineOpportunity. `current_version` is kept in sync by
# ScanSolo::ProposalVersion itself, never written here directly.
class ScanSolo::Proposal < ApplicationRecord
  self.table_name = 'scan_solo_proposals'

  belongs_to :opportunity, class_name: 'ScanSolo::PipelineOpportunity', inverse_of: :proposal
  belongs_to :current_version, class_name: 'ScanSolo::ProposalVersion', optional: true

  has_many :versions,
           class_name: 'ScanSolo::ProposalVersion',
           inverse_of: :proposal,
           dependent: :destroy

  validates :opportunity_id, uniqueness: true
end
