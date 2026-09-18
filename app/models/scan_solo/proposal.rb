# RF-77: aggregates every ScanSolo::ProposalVersion generated for a single
# ScanSolo::PipelineOpportunity. `current_version` is kept in sync by
# ScanSolo::ProposalVersion itself, never written here directly.
# == Schema Information
#
# Table name: scan_solo_proposals
#
#  id                 :bigint           not null, primary key
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  current_version_id :bigint
#  opportunity_id     :bigint           not null
#
# Indexes
#
#  index_scan_solo_proposals_on_current_version_id  (current_version_id)
#  index_scan_solo_proposals_on_opportunity_id      (opportunity_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (opportunity_id => scan_solo_pipeline_opportunities.id)
#
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
