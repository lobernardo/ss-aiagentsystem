class AddCommercialSettingsToScanSoloAiAgentConfigs < ActiveRecord::Migration[7.2]
  def change
    add_column :scan_solo_ai_agent_configs, :quote_inbox_id, :bigint
    add_column :scan_solo_ai_agent_configs, :commercial_user_id, :bigint
    add_column :scan_solo_ai_agent_configs, :quote_recipient_email, :string, null: false, default: 'comercial@scansolo.com.br'
  end
end
