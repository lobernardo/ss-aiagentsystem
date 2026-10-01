class AddDeliveryColumnsToScanSoloProposalVersions < ActiveRecord::Migration[7.2]
  def change
    add_column :scan_solo_proposal_versions, :proposal_number, :string
    add_index :scan_solo_proposal_versions, :proposal_number, unique: true
    add_column :scan_solo_proposal_versions, :valid_until, :datetime
    add_column :scan_solo_proposal_versions, :follow_up_message_id, :bigint
    add_reference :scan_solo_proposal_versions, :quote_request, index: { unique: true }, foreign_key: { to_table: :scan_solo_quote_requests }
  end
end
