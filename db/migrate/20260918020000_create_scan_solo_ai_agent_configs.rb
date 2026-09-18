class CreateScanSoloAiAgentConfigs < ActiveRecord::Migration[7.1]
  def change
    create_configs_table
    add_draft_uniqueness_index
  end

  private

  def create_configs_table
    create_table :scan_solo_ai_agent_configs do |t|
      add_identity_columns(t)
      add_playbook_columns(t)
      t.timestamps
    end
  end

  def add_identity_columns(table)
    table.references :account, null: false, index: true
    table.integer :status, null: false, default: 0
    table.references :published_version, foreign_key: { to_table: :scan_solo_ai_agent_configs }, index: true
    table.string :name
    table.boolean :enabled, null: false, default: false
    table.string :model_provider
    table.string :model_selection
    table.string :role
    table.string :objective
    table.string :persona
    table.string :tone
  end

  def add_playbook_columns(table)
    table.text :instructions
    table.text :service_rules
    table.jsonb :qualification_playbook, null: false, default: []
    table.jsonb :required_qualification_fields, null: false, default: []
    table.jsonb :restricted_information, null: false, default: []
    table.jsonb :forbidden_subjects, null: false, default: []
    table.text :transfer_criteria
    table.text :response_limits
    table.string :service_hours
  end

  # Only one draft (status: 0) row may exist per account; published rows
  # (status: 1) accumulate as immutable version history (RF-22).
  def add_draft_uniqueness_index
    add_index :scan_solo_ai_agent_configs, :account_id,
              unique: true,
              where: 'status = 0',
              name: 'index_scan_solo_ai_agent_configs_on_account_draft'
  end
end
