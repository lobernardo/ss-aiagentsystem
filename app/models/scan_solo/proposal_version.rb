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
# == Schema Information
#
# Table name: scan_solo_proposal_versions
#
#  id                           :bigint           not null, primary key
#  approved_at                  :datetime
#  approved_by_type             :string
#  artifact_url                 :string
#  currency                     :string
#  failure_reason               :string
#  generate_callback_applied_at :datetime
#  generate_requested_at        :datetime
#  is_current                   :boolean          default(TRUE), not null
#  send_callback_applied_at     :datetime
#  send_requested_at            :datetime
#  status                       :integer          default("generating"), not null
#  value                        :decimal(12, 2)
#  version_number               :integer          not null
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#  approved_by_id               :bigint
#  generate_correlation_id      :string
#  proposal_id                  :bigint           not null
#  send_correlation_id          :string
#  sent_message_id              :bigint
#
# Indexes
#
#  idx_on_approved_by_type_approved_by_id_0a2d8f1dd3             (approved_by_type,approved_by_id)
#  index_scan_solo_proposal_versions_on_current                  (proposal_id) UNIQUE WHERE (is_current = true)
#  index_scan_solo_proposal_versions_on_generate_correlation_id  (generate_correlation_id) UNIQUE
#  index_scan_solo_proposal_versions_on_proposal_and_number      (proposal_id,version_number) UNIQUE
#  index_scan_solo_proposal_versions_on_proposal_id              (proposal_id)
#  index_scan_solo_proposal_versions_on_send_correlation_id      (send_correlation_id) UNIQUE
#  index_scan_solo_proposal_versions_on_sent_message_id          (sent_message_id)
#
# Foreign Keys
#
#  fk_rails_...  (proposal_id => scan_solo_proposals.id)
#
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

  # CT-04 / RF-42: the correlation id of the version's latest operation --
  # the send once one was requested, otherwise the generate.
  def correlation_id
    send_correlation_id.presence || generate_correlation_id
  end

  # RF-40: retry/dead-letter state of the latest operation, read from the
  # MakeRequest issued under that correlation id (none for the mock provider).
  def make_request
    ScanSolo::MakeRequest.find_by(correlation_id: correlation_id) if correlation_id.present?
  end

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
