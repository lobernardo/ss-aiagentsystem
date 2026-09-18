# RF-73/RF-77/RF-79/RF-80: one immutable-ish row per generated proposal
# version. `is_current` integrity is enforced by the partial unique index
# below plus ScanSolo::ProposalVersion's own callback (T58) -- only one
# version per proposal may ever be current. `value`/`currency`/
# `artifact_url` are only ever written by ScanSolo::Proposal::CallbackHandler
# from a validated provider result (RF-76), never by GenerateService itself.
# generate_correlation_id/send_correlation_id each carry their own unique
# index and their own `*_callback_applied_at` marker so a duplicate mock (or
# future real Make) callback for either step is a guaranteed no-op (RF-80).
class CreateScanSoloProposalVersions < ActiveRecord::Migration[7.1]
  def change
    create_table :scan_solo_proposal_versions do |table|
      add_identity_columns(table)
      add_commercial_columns(table)
      add_generate_columns(table)
      add_approval_columns(table)
      add_send_columns(table)
      table.timestamps
    end

    add_index :scan_solo_proposal_versions, :proposal_id, unique: true, where: 'is_current = true',
                                                          name: 'index_scan_solo_proposal_versions_on_current'
    add_index :scan_solo_proposal_versions, %i[proposal_id version_number], unique: true,
                                                                            name: 'index_scan_solo_proposal_versions_on_proposal_and_number'
    add_index :scan_solo_proposal_versions, :generate_correlation_id, unique: true
    add_index :scan_solo_proposal_versions, :send_correlation_id, unique: true
    add_index :scan_solo_proposal_versions, %i[approved_by_type approved_by_id]
  end

  private

  def add_identity_columns(table)
    table.references :proposal, null: false, index: true, foreign_key: { to_table: :scan_solo_proposals }
    table.integer :version_number, null: false
    table.integer :status, null: false, default: 0
    table.boolean :is_current, null: false, default: true
  end

  def add_commercial_columns(table)
    table.decimal :value, precision: 12, scale: 2
    table.string :currency
    table.string :artifact_url
    table.string :failure_reason
  end

  def add_generate_columns(table)
    table.string :generate_correlation_id
    table.datetime :generate_requested_at
    table.datetime :generate_callback_applied_at
  end

  def add_approval_columns(table)
    table.datetime :approved_at
    table.references :approved_by, polymorphic: true, index: false
  end

  def add_send_columns(table)
    table.string :send_correlation_id
    table.datetime :send_requested_at
    table.datetime :send_callback_applied_at
    table.references :sent_message, index: true
  end
end
