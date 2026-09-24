# RF-61 / CT-10: everything the Execuções module shows, scoped to one
# account: cadence attempts with delivery evidence, template availability
# per mapping, Make dead letters and rejected callbacks, handoff events
# (explicit/implicit takeover, return to AI, AI-requested handoff), the
# 100 most recent errors across failed turns, failed attempts and rejected
# callbacks, and the action/handoff audit trail.
#
# AuditEvent's subject is polymorphic with no account column, so its known
# subject types are resolved back to the account through their own
# association chain (AgentActionExecution -> turn -> conversation,
# ConversationExtension -> conversation) rather than trusting an unscoped id.
class ScanSolo::ExecutionsFeedQuery
  RECENT_ERRORS_LIMIT = 100
  HANDOFF_EVENT_TYPES = %w[handoff.takeover handoff.return_to_ai agent_action.human_handoff].freeze

  Feed = Struct.new(:cadence_evidence, :template_availability, :dead_letters, :callback_errors, :handoff_events, :recent_errors,
                    :audit_events, keyword_init: true)
  DeadLetter = Struct.new(:make_request, :proposal_version, keyword_init: true)
  HandoffEvent = Struct.new(:id, :conversation_id, :event_type, :trigger, :actor_type, :actor_id, :correlation_id, :created_at,
                            keyword_init: true)
  RecentError = Struct.new(:kind, :id, :reason, :correlation_id, :occurred_at, keyword_init: true)

  def self.call(account:)
    new(account: account).call
  end

  def initialize(account:)
    @account = account
  end

  def call
    Feed.new(
      cadence_evidence: cadence_evidence,
      template_availability: ScanSolo::Messaging::TemplateAvailabilityReport.call(account: account),
      dead_letters: dead_letters,
      callback_errors: callback_errors.limit(RECENT_ERRORS_LIMIT).to_a,
      handoff_events: handoff_events,
      recent_errors: recent_errors,
      audit_events: audit_events.order(created_at: :desc).limit(RECENT_ERRORS_LIMIT)
    )
  end

  private

  attr_reader :account

  def cadence_evidence
    ScanSolo::CadenceEnrollment.joins(:opportunity)
                               .where(scan_solo_pipeline_opportunities: { account_id: account.id })
                               .includes(:opportunity, :cadence_definition, :attempts)
                               .order(updated_at: :desc)
  end

  def dead_letters
    requests = ScanSolo::Make::DeadLetterQuery.call(account: account).to_a
    versions = ScanSolo::ProposalVersion.where(id: requests.map { |request| request.payload['proposal_version_id'] }).index_by(&:id)
    requests.map { |request| DeadLetter.new(make_request: request, proposal_version: versions[request.payload['proposal_version_id']]) }
  end

  def callback_errors
    ScanSolo::MakeCallback.where(correlation_id: ScanSolo::MakeRequest.where(account: account).select(:correlation_id))
                          .where(applied: false)
                          .order(created_at: :desc)
  end

  def handoff_events
    events = audit_events.where(event_type: HANDOFF_EVENT_TYPES).includes(:subject).order(created_at: :desc).limit(RECENT_ERRORS_LIMIT)
    events.map do |event|
      HandoffEvent.new(
        id: event.id, conversation_id: handoff_conversation_id(event), event_type: event.event_type, trigger: handoff_trigger(event),
        actor_type: event.actor_type, actor_id: event.actor_id, correlation_id: event.correlation_id, created_at: event.created_at
      )
    end
  end

  def handoff_conversation_id(event)
    event.subject.is_a?(ScanSolo::ConversationExtension) ? event.subject.conversation_id : event.subject.turn&.conversation_id
  end

  def handoff_trigger(event)
    return 'ai_action' if event.event_type == 'agent_action.human_handoff'

    event.payload['trigger'] == 'human_reply' ? 'implicit' : 'explicit'
  end

  def recent_errors
    (failed_turn_errors + failed_attempt_errors + rejected_callback_errors).sort_by(&:occurred_at).reverse.first(RECENT_ERRORS_LIMIT)
  end

  def failed_turn_errors
    ScanSolo::AiTurn.failed.joins(:conversation).where(conversations: { account_id: account.id })
                    .order(updated_at: :desc).limit(RECENT_ERRORS_LIMIT)
                    .map do |turn|
      RecentError.new(kind: 'ai_turn', id: turn.id, reason: turn.failure_reason.to_s, correlation_id: turn.correlation_id,
                      occurred_at: turn.updated_at)
    end
  end

  def failed_attempt_errors
    ScanSolo::CadenceAttempt.failed.joins(enrollment: :opportunity)
                            .where(scan_solo_pipeline_opportunities: { account_id: account.id })
                            .order(updated_at: :desc).limit(RECENT_ERRORS_LIMIT)
                            .map do |attempt|
      RecentError.new(kind: 'cadence_attempt', id: attempt.id, reason: attempt.external_error.presence || attempt.last_block_reason || 'failed',
                      correlation_id: nil, occurred_at: attempt.updated_at)
    end
  end

  def rejected_callback_errors
    callback_errors.limit(RECENT_ERRORS_LIMIT).map do |callback|
      RecentError.new(kind: 'make_callback', id: callback.id, reason: callback.rejection_reason, correlation_id: callback.correlation_id,
                      occurred_at: callback.created_at)
    end
  end

  def audit_events
    ScanSolo::AuditEvent.where(subject_type: 'ScanSolo::AgentActionExecution', subject_id: agent_action_execution_ids)
                        .or(ScanSolo::AuditEvent.where(subject_type: 'ScanSolo::ConversationExtension', subject_id: conversation_extension_ids))
  end

  def agent_action_execution_ids
    ScanSolo::AgentActionExecution.joins(turn: :conversation).where(conversations: { account_id: account.id }).select(:id)
  end

  def conversation_extension_ids
    ScanSolo::ConversationExtension.joins(:conversation).where(conversations: { account_id: account.id }).select(:id)
  end
end
