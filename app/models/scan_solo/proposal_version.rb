# RF-77: only one version is `is_current: true` per proposal at a time,
# guarded by a DB partial-unique index (the migration) plus the callback
# below -- generating a new version marks the previous one non-current in
# the same transaction, and mirrors the new pointer onto the parent
# Proposal#current_version_id so approve/send always resolve "the current
# version" from a single column instead of a fresh query per caller.
#
# `value`/`currency`/`artifact_url` are intentionally never set by any
# validation or callback here -- the only writer of those fields is
# ScanSolo::Proposal::CallbackHandler, reached exclusively from a validated
# provider result (RF-76).
class ScanSolo::ProposalVersion < ApplicationRecord
  self.table_name = 'scan_solo_proposal_versions'

  belongs_to :proposal, class_name: 'ScanSolo::Proposal', inverse_of: :versions
  belongs_to :approved_by, polymorphic: true, optional: true
  belongs_to :sent_message, class_name: 'Message', optional: true

  enum status: { generating: 0, generated: 1, approved: 2, sent: 3, failed: 4 }

  before_validation :assign_version_number, on: :create
  before_create :unmark_previous_current, if: :is_current?
  after_create :sync_current_version_pointer, if: :is_current?
  after_update :sync_current_version_pointer, if: -> { saved_change_to_is_current? && is_current? }

  validates :version_number, presence: true, uniqueness: { scope: :proposal_id }

  def approval_required?
    config = ScanSolo::AiAgentConfig.published_for(proposal.opportunity.account)
    config.nil? || config.require_proposal_approval
  end

  private

  def assign_version_number
    self.version_number ||= proposal.versions.maximum(:version_number).to_i + 1
  end

  def unmark_previous_current
    proposal.versions.where(is_current: true).update_all(is_current: false) # rubocop:disable Rails/SkipsModelValidations
  end

  def sync_current_version_pointer
    proposal.update_column(:current_version_id, id) # rubocop:disable Rails/SkipsModelValidations
  end
end
