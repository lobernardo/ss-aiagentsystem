class CreateScanSoloPipelineStageEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :scan_solo_pipeline_stage_events do |t|
      t.references :opportunity, null: false, index: true
      t.string :from_stage, null: false
      t.string :to_stage, null: false
      t.references :actor, polymorphic: true, index: false

      t.datetime :created_at, null: false
    end

    add_index :scan_solo_pipeline_stage_events, [:actor_type, :actor_id]
  end
end
