# RF-48: registers the minimum commercial action set and is the single
# place mapping an action id to the Ruby class that performs its side
# effect. Wires every registered handler through ScanSolo::Actions::Executor
# (T38), so classification, schema validation, idempotency, confirmation
# gating, and the audit trail apply uniformly regardless of which action is
# invoked. Action ids here match ScanSolo::AiTurn::InputGuardrail::ALL_ACTIONS.
class ScanSolo::Actions::Registry
  HANDLERS = {
    'qualification_field' => ScanSolo::Actions::QualificationFieldAction,
    'stage_transition' => ScanSolo::Actions::StageTransitionAction,
    'private_note' => ScanSolo::Actions::PrivateNoteAction,
    'proposal_generate' => ScanSolo::Actions::ProposalActions::Generate,
    'proposal_approve' => ScanSolo::Actions::ProposalActions::Approve,
    'proposal_send' => ScanSolo::Actions::ProposalActions::Send,
    'cadence_signal' => ScanSolo::Actions::CadenceSignalAction,
    'human_handoff' => ScanSolo::Actions::HandoffAction
  }.freeze

  # Idempotent bulk sync of every handler's classification/schema into
  # scan_solo_agent_actions -- useful to pre-register the full set at once
  # (e.g. an admin listing). `.call` below also self-registers the single
  # action it invokes, so no separate boot-time seeding step is required
  # for the executor to function.
  def self.register_all!
    HANDLERS.each_key { |action_id| sync_registration!(action_id) }
  end

  # rubocop:disable Metrics/ParameterLists
  def self.call(action_id:, params:, correlation_id:, idempotency_key:, actor: nil, turn: nil, confirmed: false)
    # rubocop:enable Metrics/ParameterLists
    sync_registration!(action_id)

    ScanSolo::Actions::Executor.call(
      action_id: action_id, params: params, correlation_id: correlation_id, idempotency_key: idempotency_key,
      actor: actor, turn: turn, confirmed: confirmed
    ) { |validated_params| handler_for(action_id).call(params: validated_params, actor: actor, turn: turn) }
  end

  def self.handler_for(action_id)
    HANDLERS.fetch(action_id.to_s) { raise ScanSolo::Actions::Executor::UnregisteredActionError, action_id }
  end

  def self.sync_registration!(action_id)
    handler_class = handler_for(action_id)

    action = ScanSolo::AgentAction.find_or_initialize_by(action_id: action_id.to_s)
    action.classification = handler_class::CLASSIFICATION
    action.schema = handler_class::SCHEMA
    action.save!
  end
end
