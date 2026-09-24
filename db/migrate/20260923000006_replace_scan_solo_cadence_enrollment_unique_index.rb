class ReplaceScanSoloCadenceEnrollmentUniqueIndex < ActiveRecord::Migration[7.2]
  def up
    remove_index :scan_solo_cadence_enrollments, name: 'idx_scansolo_cadence_enrollments_on_opportunity_and_definition'
    add_index :scan_solo_cadence_enrollments, %i[opportunity_id cadence_definition_id],
              unique: true, name: 'idx_scansolo_cadence_enrollments_on_opportunity_and_definition', where: 'status IN (0, 1)'
  end

  def down
    remove_index :scan_solo_cadence_enrollments, name: 'idx_scansolo_cadence_enrollments_on_opportunity_and_definition'
    add_index :scan_solo_cadence_enrollments, %i[opportunity_id cadence_definition_id],
              unique: true, name: 'idx_scansolo_cadence_enrollments_on_opportunity_and_definition'
  end
end
