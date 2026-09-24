class AddProductionFieldsToScanSoloAiAgentConfigs < ActiveRecord::Migration[7.2]
  def change
    add_column :scan_solo_ai_agent_configs, :allowed_inbox_ids, :jsonb, null: false, default: []
    add_column :scan_solo_ai_agent_configs, :opt_out_keywords, :jsonb, null: false, default: %w[PARAR SAIR STOP]
  end
end
