class CreateScanSoloPipelineOpportunities < ActiveRecord::Migration[7.1]
  def change
    create_table :scan_solo_pipeline_opportunities do |t|
      t.references :account, null: false, index: true
      t.references :contact, null: false, index: true
      t.references :conversation, null: false, index: { unique: true }
      t.references :owner, index: true
      t.integer :stage, null: false, default: 0
      t.datetime :last_customer_interaction_at

      t.timestamps
    end
  end
end
