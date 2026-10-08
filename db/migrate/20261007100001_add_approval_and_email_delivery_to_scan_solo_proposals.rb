class AddApprovalAndEmailDeliveryToScanSoloProposals < ActiveRecord::Migration[7.2]
  def change
    add_column :scan_solo_proposal_versions, :rejected_at, :datetime
    add_reference :scan_solo_proposal_versions, :rejected_by, polymorphic: true
    add_column :scan_solo_proposal_versions, :rejection_reason, :text
    add_column :scan_solo_proposal_versions, :approval_requested_at, :datetime
    add_column :scan_solo_proposal_versions, :approval_request_message_id, :bigint
    add_column :scan_solo_proposal_versions, :notice_message_id, :bigint
    add_index :scan_solo_proposal_versions, :notice_message_id
    add_column :scan_solo_proposal_versions, :notice_failure_reason, :string
    add_column :scan_solo_proposal_versions, :artifact_sha256, :string
    add_column :scan_solo_proposals, :email_conversation_id, :bigint
    add_index :scan_solo_proposals, :email_conversation_id, unique: true
  end
end
