# CT-04 / RF-46 / RF-47 / RNF-01: the sole path from a turn's decided
# action request to any side effect. Accepts only a registered action id
# plus schema-validated structured parameters -- a parameter that isn't
# part of the action's declared JSON schema (e.g. a free-form URL/command/
# SQL string) is rejected here, before the side-effect block ever runs
# (RF-47), because every registered schema is closed (`additionalProperties:
# false`). Every invocation is keyed by idempotency_key: a repeat call with
# the same key never re-runs an already-executed side effect (RNF-01), and
# every execution is linked to its originating turn's correlation id via an
# audit record (RF-46). A `requires_confirmation` action is gated by
# ScanSolo::Actions::ConfirmationGate and stays pending with zero side
# effects until a call arrives with `confirmed: true` for that same
# idempotency key (RF-49).
class ScanSolo::Actions::Executor
  class UnregisteredActionError < StandardError; end
  class InvalidParamsError < StandardError; end

  Result = Struct.new(:execution, :side_effect_result, :pending, keyword_init: true)

  # rubocop:disable Metrics/ParameterLists
  def self.call(action_id:, params:, correlation_id:, idempotency_key:, actor: nil, turn: nil, confirmed: false, &side_effect)
    new(
      action_id: action_id, params: params, correlation_id: correlation_id, idempotency_key: idempotency_key,
      actor: actor, turn: turn, confirmed: confirmed, side_effect: side_effect
    ).call
  end

  def initialize(action_id:, params:, correlation_id:, idempotency_key:, actor:, turn:, confirmed:, side_effect:)
    # rubocop:enable Metrics/ParameterLists
    @action_id = action_id.to_s
    @params = params || {}
    @correlation_id = correlation_id
    @idempotency_key = idempotency_key
    @actor = actor
    @turn = turn
    @confirmed = confirmed
    @side_effect = side_effect
  end

  def call
    action = authorized_action!
    existing = ScanSolo::AgentActionExecution.find_by(idempotency_key: idempotency_key)

    return resume_existing(existing, action) if existing.present?

    validate_params!(action)
    execution = create_execution!(action)
    attempt(execution, action)
  end

  private

  attr_reader :action_id, :params, :correlation_id, :idempotency_key, :actor, :turn, :confirmed, :side_effect

  def authorized_action!
    action = ScanSolo::AgentAction.find_by(action_id: action_id)
    raise UnregisteredActionError, action_id if action.blank? || action.disabled?

    action
  end

  def validate_params!(action)
    schemer = JSONSchemer.schema(action.schema)
    errors = schemer.validate(params.deep_stringify_keys).to_a

    raise InvalidParamsError, errors.pluck('error').join('; ') if errors.any?
  end

  def create_execution!(action)
    ScanSolo::AgentActionExecution.create!(
      action_id: action.action_id,
      turn: turn,
      correlation_id: correlation_id,
      idempotency_key: idempotency_key,
      params: params,
      status: :pending
    )
  end

  def resume_existing(execution, action)
    return Result.new(execution: execution, side_effect_result: nil, pending: execution.pending?) unless execution.pending? && confirmed

    attempt(execution, action)
  end

  def attempt(execution, action)
    if ScanSolo::Actions::ConfirmationGate.blocked?(action: action, confirmed: confirmed)
      return Result.new(execution: execution, side_effect_result: nil, pending: true)
    end

    run!(execution, action)
  end

  def run!(execution, action)
    execution.update!(confirmed_at: Time.current) if confirmed && execution.confirmed_at.blank?

    result = side_effect.call(params.deep_symbolize_keys)
    execution.update!(status: :executed)

    audit_event = ScanSolo::AuditLogger.record!(
      subject: execution,
      event_type: "agent_action.#{action.action_id}",
      actor: actor,
      correlation_id: correlation_id,
      payload: { params: params, result: serialize_result(result) }
    )
    execution.update!(audit_event: audit_event)

    Result.new(execution: execution, side_effect_result: result, pending: false)
  rescue StandardError => e
    execution.update!(status: :failed)
    raise e
  end

  def serialize_result(result)
    return result.attributes if result.respond_to?(:attributes)
    return result.to_h if result.respond_to?(:to_h)

    result
  end
end
