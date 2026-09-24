class ReplaceScanSoloMakeCallbacksCorrelationIndex < ActiveRecord::Migration[7.2]
  def up
    remove_index :scan_solo_make_callbacks, name: 'index_scan_solo_make_callbacks_on_correlation_id'
    add_index :scan_solo_make_callbacks, :correlation_id,
              unique: true, name: 'index_scan_solo_make_callbacks_on_correlation_id', where: 'applied = true'
  end

  def down
    remove_index :scan_solo_make_callbacks, name: 'index_scan_solo_make_callbacks_on_correlation_id'
    add_index :scan_solo_make_callbacks, :correlation_id,
              unique: true, name: 'index_scan_solo_make_callbacks_on_correlation_id'
  end
end
