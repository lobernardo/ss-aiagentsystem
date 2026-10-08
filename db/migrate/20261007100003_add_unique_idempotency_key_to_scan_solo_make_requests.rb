class AddUniqueIdempotencyKeyToScanSoloMakeRequests < ActiveRecord::Migration[7.2]
  def change
    reversible { |direction| direction.up { abort_on_duplicate_idempotency_keys } }
    add_index :scan_solo_make_requests, :idempotency_key, unique: true
  end

  private

  # RF-24: never alter records to make the index fit; fail before any DDL instead.
  def abort_on_duplicate_idempotency_keys
    duplicated_keys = select_values(<<~SQL.squish)
      SELECT idempotency_key FROM scan_solo_make_requests GROUP BY idempotency_key HAVING count(*) > 1 ORDER BY idempotency_key
    SQL
    raise ActiveRecord::MigrationError, "duplicate idempotency_key: #{duplicated_keys.join(', ')}" if duplicated_keys.any?
  end
end
