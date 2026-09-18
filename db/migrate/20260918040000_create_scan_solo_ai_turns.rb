# Additive telemetry table for the canonical guarded AI turn flow (RF-24).
# The unique index on message_id is the DB-level backstop for the RF-36
# dedupe guarantee ("no more than one AI turn/response for the same inbound
# message id, including under Sidekiq job retry") — enforced at the
# constraint level, not only in application code, so a concurrent retry
# racing the first attempt raises RecordNotUnique instead of silently
# creating a second turn/response. correlation_id is unique so every turn
# is independently queryable/traceable (RF-24 AC).
class CreateScanSoloAiTurns < ActiveRecord::Migration[7.1]
  def change
    create_table :scan_solo_ai_turns do |t|
      add_identity_columns(t)
      add_telemetry_columns(t)
      add_evidence_columns(t)
      t.timestamps
    end

    add_index :scan_solo_ai_turns, :message_id, unique: true
    add_index :scan_solo_ai_turns, :correlation_id, unique: true
  end

  private

  def add_identity_columns(table)
    table.references :message, null: false, index: false
    table.references :conversation, null: false, index: true
    table.string :correlation_id, null: false
    table.integer :invocation_status, null: false, default: 0
  end

  def add_telemetry_columns(table)
    table.string :model_provider
    table.string :model_reference
    table.integer :input_tokens
    table.integer :output_tokens
    table.decimal :cost_estimate, precision: 10, scale: 6
    table.integer :latency_ms
    table.text :failure_reason
  end

  def add_evidence_columns(table)
    table.jsonb :context_snapshot, null: false, default: {}
    table.jsonb :guardrail_outcome, null: false, default: {}
    table.jsonb :knowledge_evidence, null: false, default: []
    table.jsonb :action_evidence, null: false, default: []
  end
end
