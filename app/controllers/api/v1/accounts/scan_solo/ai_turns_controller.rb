# UI-04: read-only per-turn telemetry/evidence viewer, queryable by
# correlation id (RF-24) — every turn already carries its guardrail
# outcome, knowledge evidence, action evidence, and context snapshot
# (ScanSolo::AiTurn::TurnOrchestrator), so this controller only ever reads,
# never mutates, turn state.
class Api::V1::Accounts::ScanSolo::AiTurnsController < Api::V1::Accounts::ScanSolo::BaseController
  before_action :set_turn, only: [:show]

  def index
    authorize(::ScanSolo::AiTurn)
    @turns = scoped_turns.order(created_at: :desc).limit(50)
  end

  def show
    authorize(@turn)
  end

  private

  def set_turn
    @turn = scoped_turns.find_by!(correlation_id: params[:id])
  end

  def scoped_turns
    ::ScanSolo::AiTurn.where(conversation_id: Current.account.conversations.select(:id))
  end
end
