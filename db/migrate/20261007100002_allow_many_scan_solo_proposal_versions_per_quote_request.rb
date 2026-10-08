class AllowManyScanSoloProposalVersionsPerQuoteRequest < ActiveRecord::Migration[7.2]
  # generating 0, approved 2, awaiting_approval 5: at most one open version per quote request (RF-07).
  OPEN_STATUSES = 'status IN (0, 2, 5)'.freeze

  def up
    remove_index :scan_solo_proposal_versions, name: 'index_scan_solo_proposal_versions_on_quote_request_id'
    add_index :scan_solo_proposal_versions, :quote_request_id, name: 'index_scan_solo_proposal_versions_on_quote_request_id'
    add_index :scan_solo_proposal_versions, :quote_request_id,
              unique: true, name: 'index_scan_solo_proposal_versions_one_open_per_quote_request', where: OPEN_STATUSES
  end

  def down
    remove_index :scan_solo_proposal_versions, name: 'index_scan_solo_proposal_versions_one_open_per_quote_request'
    remove_index :scan_solo_proposal_versions, name: 'index_scan_solo_proposal_versions_on_quote_request_id'
    add_index :scan_solo_proposal_versions, :quote_request_id,
              unique: true, name: 'index_scan_solo_proposal_versions_on_quote_request_id'
  end
end
