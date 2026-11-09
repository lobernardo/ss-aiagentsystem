class AddCommercialWhatsappNumberToScanSoloAiAgentConfigs < ActiveRecord::Migration[7.2]
  def change
    add_column :scan_solo_ai_agent_configs, :commercial_whatsapp_number, :string
  end
end
