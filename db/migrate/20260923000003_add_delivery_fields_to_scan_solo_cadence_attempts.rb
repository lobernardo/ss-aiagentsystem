class AddDeliveryFieldsToScanSoloCadenceAttempts < ActiveRecord::Migration[7.2]
  def change
    add_reference :scan_solo_cadence_attempts, :message, foreign_key: true
    add_column :scan_solo_cadence_attempts, :last_block_reason, :string
    add_column :scan_solo_cadence_attempts, :last_checked_at, :datetime
    add_column :scan_solo_cadence_attempts, :external_error, :text
  end
end
