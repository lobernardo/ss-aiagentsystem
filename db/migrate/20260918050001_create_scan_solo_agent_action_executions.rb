# Additive execution-log table for T38's deterministic executor. The unique
# index on idempotency_key is the DB-level backstop for RNF-01 ("invoking
# the same action twice with the same idempotency key produces the side
# effect exactly once") -- enforced at the constraint level, not only in
# application code, so a concurrent retry racing the first attempt raises
# RecordNotUnique instead of silently re-running the side effect.
class CreateScanSoloAgentActionExecutions < ActiveRecord::Migration[7.1]
  def change
    create_table :scan_solo_agent_action_executions do |t|
      t.string :action_id, null: false
      t.references :turn, null: true, index: true, foreign_key: { to_table: :scan_solo_ai_turns }
      t.string :correlation_id, null: false
      t.string :idempotency_key, null: false
      t.jsonb :params, null: false, default: {}
      t.integer :status, null: false, default: 0
      t.datetime :confirmed_at
      t.references :audit_event, null: true, index: true, foreign_key: { to_table: :scan_solo_audit_events }

      t.timestamps
    end

    add_index :scan_solo_agent_action_executions, :action_id
    add_index :scan_solo_agent_action_executions, :correlation_id
    add_index :scan_solo_agent_action_executions, :idempotency_key, unique: true
  end
end
