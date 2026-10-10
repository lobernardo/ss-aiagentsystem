class AddQuoteEmailValidationModeToScanSoloAiAgentConfigs < ActiveRecord::Migration[7.2]
  def change
    add_column :scan_solo_ai_agent_configs, :quote_email_validation_mode, :boolean, default: true, null: false
  end
end
