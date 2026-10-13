class AddCollectionToScanSoloLeadStates < ActiveRecord::Migration[7.2]
  def change
    add_column :scan_solo_lead_states, :collection_offered_at, :datetime
    add_column :scan_solo_lead_states, :collection_mode, :string
  end
end
