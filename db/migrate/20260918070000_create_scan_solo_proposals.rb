# RF-77: one ScanSolo::Proposal per opportunity, aggregating its versions.
# `current_version_id` mirrors whichever version is `is_current: true`,
# kept in sync by ScanSolo::ProposalVersion itself (T58) so approve/send
# always resolve "the current version" from a single column rather than a
# fresh query per caller. No foreign_key constraint on current_version_id:
# scan_solo_proposal_versions is created by the next migration, after this
# one.
class CreateScanSoloProposals < ActiveRecord::Migration[7.1]
  def change
    create_table :scan_solo_proposals do |t|
      t.references :opportunity, null: false, index: { unique: true },
                                 foreign_key: { to_table: :scan_solo_pipeline_opportunities }
      t.references :current_version, index: true

      t.timestamps
    end
  end
end
