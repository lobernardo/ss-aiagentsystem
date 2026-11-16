class AddEmailRedirectCountToScanSoloPipelineOpportunities < ActiveRecord::Migration[7.2]
  def change
    add_column :scan_solo_pipeline_opportunities, :email_redirect_count, :integer, null: false, default: 0
  end
end
