# RF-08/RNF-02: registered in config/schedule.yml (every 5 minutes) so no AI
# turn stays `pending` for longer than ScanSolo::AI_TURN_STALE_THRESHOLD. Each
# turn is failed with `stale_pending` under its row lock; the orchestrator
# re-reads the turn under the same lock before sending, so a swept turn never
# sends a message afterwards.
class ScanSolo::StaleTurnSweeperJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    ScanSolo::AiTurn.pending.where(created_at: ...ScanSolo::AI_TURN_STALE_THRESHOLD.ago).find_each do |turn|
      turn.with_lock do
        turn.update!(invocation_status: :failed, failure_reason: 'stale_pending') if turn.pending?
      end
    end
  end
end
