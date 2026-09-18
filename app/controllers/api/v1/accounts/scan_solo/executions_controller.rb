# UI-09: read-only Execuções e auditoria endpoint aggregating cadence
# attempt evidence (T50), Make outbound dead-letter and inbound callback
# error visibility (T70), and action audit records (T38/T08) into one
# queryable, account-scoped response. AuditEvent's subject is polymorphic
# with no account column of its own, so its two known subject types are
# resolved back to the account through their own association chain
# (AgentActionExecution -> turn -> conversation, ConversationExtension ->
# conversation) rather than trusting an unscoped id.
class Api::V1::Accounts::ScanSolo::ExecutionsController < Api::V1::Accounts::ScanSolo::BaseController
  def index
    authorize(Current.account, :index?, policy_class: ::ScanSolo::ExecutionPolicy)

    @cadence_evidence = scoped_enrollments
    @make_dead_letters = ::ScanSolo::Make::DeadLetterQuery.call(account: Current.account)
    @make_callback_errors = scoped_callback_errors
    @audit_events = scoped_audit_events
  end

  private

  def scoped_enrollments
    ::ScanSolo::CadenceEnrollment.joins(:opportunity)
                                 .where(scan_solo_pipeline_opportunities: { account_id: Current.account.id })
                                 .includes(:opportunity, :cadence_definition, :attempts)
                                 .order(updated_at: :desc)
  end

  def scoped_callback_errors
    ::ScanSolo::MakeCallback.where(correlation_id: account_make_request_correlation_ids)
                            .where(applied: false)
                            .order(created_at: :desc)
  end

  def account_make_request_correlation_ids
    ::ScanSolo::MakeRequest.where(account: Current.account).select(:correlation_id)
  end

  def scoped_audit_events
    ::ScanSolo::AuditEvent.where(subject_type: 'ScanSolo::AgentActionExecution', subject_id: agent_action_execution_ids)
                          .or(::ScanSolo::AuditEvent.where(subject_type: 'ScanSolo::ConversationExtension', subject_id: conversation_extension_ids))
                          .order(created_at: :desc)
                          .limit(100)
  end

  def agent_action_execution_ids
    ::ScanSolo::AgentActionExecution.joins(turn: :conversation)
                                    .where(conversations: { account_id: Current.account.id })
                                    .select(:id)
  end

  def conversation_extension_ids
    ::ScanSolo::ConversationExtension.joins(:conversation)
                                     .where(conversations: { account_id: Current.account.id })
                                     .select(:id)
  end
end
