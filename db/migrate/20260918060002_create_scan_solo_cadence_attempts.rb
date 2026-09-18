# RF-62: one immutable evidence row per cadence attempt (cadence version,
# template reference, scheduled time, actual send time, result). Rows are
# only ever inserted or have `sent_at`/`result` set exactly once by
# ScanSolo::Cadence::AttemptEvidenceRecorder -- enforced at the application
# level, since a terminal result is never expected to change here.
class CreateScanSoloCadenceAttempts < ActiveRecord::Migration[7.1]
  def change
    create_table :scan_solo_cadence_attempts do |t|
      t.references :enrollment, null: false, index: true,
                                 foreign_key: { to_table: :scan_solo_cadence_enrollments }
      t.integer :step, null: false
      t.integer :cadence_version, null: false
      t.string :template_reference, null: false
      t.datetime :scheduled_at, null: false
      t.datetime :sent_at
      t.integer :result, null: false, default: 0

      t.timestamps
    end

    add_index :scan_solo_cadence_attempts, %i[enrollment_id step], unique: true
  end
end
