# RF-59: enrollment idempotency is enforced at the DB level by the unique
# index on (opportunity_id, cadence_definition_id) -- a concurrent duplicate
# enrollment attempt raises ActiveRecord::RecordNotUnique instead of
# silently creating a second active enrollment.
class CreateScanSoloCadenceEnrollments < ActiveRecord::Migration[7.1]
  def change
    create_table :scan_solo_cadence_enrollments do |t|
      t.references :opportunity, null: false, index: true,
                                  foreign_key: { to_table: :scan_solo_pipeline_opportunities }
      t.references :cadence_definition, null: false, index: true,
                                         foreign_key: { to_table: :scan_solo_cadence_definitions }
      t.integer :status, null: false, default: 0
      t.integer :current_step, null: false, default: 0
      t.datetime :next_attempt_at
      t.datetime :paused_at

      t.timestamps
    end

    add_index :scan_solo_cadence_enrollments, %i[opportunity_id cadence_definition_id], unique: true,
              name: 'idx_scansolo_cadence_enrollments_on_opportunity_and_definition'
  end
end
