class AddLeadSourceToScanSoloPipelineOpportunities < ActiveRecord::Migration[7.2]
  def change
    add_column :scan_solo_pipeline_opportunities, :lead_source, :string
    add_check_constraint :scan_solo_pipeline_opportunities, "lead_source IN ('website','manual')",
                         name: 'scan_solo_pipeline_opportunities_lead_source_check'
  end
end
