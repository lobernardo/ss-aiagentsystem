class CreateScanSoloProposalTemplates < ActiveRecord::Migration[7.2]
  def change
    create_table :scan_solo_proposal_templates do |t|
      t.references :account, null: false, index: false, foreign_key: true
      t.references :uploaded_by, index: false, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :filename, null: false
      t.bigint :byte_size, null: false
      t.string :sha256, null: false
      t.boolean :active, null: false, default: false

      t.timestamps
    end
    add_index :scan_solo_proposal_templates, :account_id, unique: true, where: 'active',
                                                          name: 'index_scan_solo_proposal_templates_one_active_per_account'
    add_index :scan_solo_proposal_templates, [:account_id, :created_at], name: 'index_scan_solo_proposal_templates_on_account_and_created_at'
  end
end
