class AddCommercialEscalationToScanSoloPipelineOpportunities < ActiveRecord::Migration[7.2]
  def change
    add_column :scan_solo_pipeline_opportunities, :escalated_to_commercial_at, :datetime
    add_column :scan_solo_pipeline_opportunities, :escalation_reason, :string
  end
end
