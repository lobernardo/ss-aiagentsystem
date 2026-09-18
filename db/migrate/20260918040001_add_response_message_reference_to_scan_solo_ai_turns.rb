# Additive column: scan_solo_ai_turns.message_id (unique, RF-36 dedupe key)
# always references the triggering *inbound* message. RF-43 also requires
# the turn's evidence record to reference the *outbound* message it sent,
# which is a distinct row — this column carries that second reference.
class AddResponseMessageReferenceToScanSoloAiTurns < ActiveRecord::Migration[7.1]
  def change
    add_reference :scan_solo_ai_turns, :response_message, index: true
  end
end
