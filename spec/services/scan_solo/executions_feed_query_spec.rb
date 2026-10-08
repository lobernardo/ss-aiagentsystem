# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::ExecutionsFeedQuery do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :em_contato)
  end
  let(:definition) { ScanSolo::CadenceDefinition.create!(stage: 'em_contato', version: 1, offsets: [24, 48]) }
  let(:enrollment) do
    ScanSolo::CadenceEnrollment.create!(opportunity: opportunity, cadence_definition: definition, status: :active, current_step: 1)
  end
  let(:extension) { ScanSolo::ConversationExtension.resolve_for(conversation) }

  def feed
    described_class.call(account: account)
  end

  def failed_turn(reason)
    message = create(:message, account: account, conversation: conversation, message_type: :incoming, sender: contact)
    ScanSolo::AiTurn.create!(message: message, conversation: conversation, correlation_id: SecureRandom.uuid,
                             invocation_status: :failed, failure_reason: reason)
  end

  def rejected_callback(correlation_id, reason: 'schema_invalid')
    ScanSolo::MakeCallback.create!(correlation_id: correlation_id, action: 'proposal.generate', payload: {}, applied: false,
                                   signature_valid: true, rejection_reason: reason)
  end

  it 'returns cadence attempts with their delivery evidence' do
    attempt = ScanSolo::CadenceAttempt.create!(enrollment: enrollment, step: 1, cadence_version: 1, template_reference: 't1',
                                               scheduled_at: 1.hour.ago, result: :failed, external_error: '131047 re-engagement',
                                               last_block_reason: 'template_paused', last_checked_at: 2.hours.ago)

    expect(feed.cadence_evidence.first.attempts).to contain_exactly(attempt)
  end

  it 'returns one template availability row per stage step plus the CT-09 slot rows' do
    definition

    rows = feed.template_availability
    # CT-09 (RNF-11): the manual-lead and follow-up slots join the proposal send row; CT-07 adds the email notice slot.
    expect(rows.pluck(:stage, :step)).to eq(
      [['em_contato', 1], ['em_contato', 2], ['proposta_enviada', nil], ['lead_manual_inicial', nil], ['proposta_acompanhamento', nil],
       ['proposta_aviso_email', nil]]
    )
    expect(rows.first).to include(:availability, :block_reason, :meta_status, :last_synced_at)
  end

  it 'returns dead letters with the proposal version to reprocess' do
    proposal = ScanSolo::Proposal.create!(opportunity: opportunity)
    version = proposal.versions.create!(status: :failed, failure_reason: 'timeout')
    request = ScanSolo::MakeRequest.create!(account: account, correlation_id: SecureRandom.uuid, idempotency_key: 'k', action: 'proposal.generate',
                                            payload: { proposal_version_id: version.id }, status: :failed, retry_count: 3)

    dead_letter = feed.dead_letters.sole
    expect(dead_letter.make_request).to eq(request)
    expect(dead_letter.proposal_version).to eq(version)
  end

  it 'returns rejected callbacks with their reason, scoped to the account requests' do
    correlation_id = SecureRandom.uuid
    ScanSolo::MakeRequest.create!(account: account, correlation_id: correlation_id, idempotency_key: 'k', action: 'proposal.generate',
                                  payload: {}, status: :sent)
    callback = rejected_callback(correlation_id)
    rejected_callback(SecureRandom.uuid)

    expect(feed.callback_errors).to eq([callback])
  end

  it 'classifies handoff events as implicit, explicit or ai_action' do
    ScanSolo::AuditLogger.record!(subject: extension, event_type: 'handoff.takeover', actor: admin, correlation_id: 'c1',
                                  payload: { trigger: 'human_reply' })
    ScanSolo::AuditLogger.record!(subject: extension, event_type: 'handoff.takeover', actor: admin, correlation_id: 'c2',
                                  payload: { trigger: 'explicit' })
    ScanSolo::AuditLogger.record!(subject: extension, event_type: 'handoff.return_to_ai', actor: admin, correlation_id: 'c3', payload: {})
    turn = failed_turn('x')
    ScanSolo::AgentAction.create!(action_id: 'human_handoff', classification: :automatic, schema: {})
    execution = ScanSolo::AgentActionExecution.create!(action_id: 'human_handoff', turn: turn, correlation_id: 'c4', idempotency_key: 'i',
                                                       params: {}, status: :executed)
    ScanSolo::AuditLogger.record!(subject: execution, event_type: 'agent_action.human_handoff', correlation_id: 'c4', payload: {})

    events = feed.handoff_events.index_by(&:correlation_id)
    expect(events.transform_values(&:trigger)).to eq('c1' => 'implicit', 'c2' => 'explicit', 'c3' => 'explicit', 'c4' => 'ai_action')
    expect(events.values.map(&:conversation_id).uniq).to eq([conversation.id])
    expect(events['c1']).to have_attributes(actor_type: 'User', actor_id: admin.id, event_type: 'handoff.takeover')
  end

  it 'merges failed turns, failed attempts and rejected callbacks into recent errors, newest first' do
    turn = travel_to(3.minutes.ago) { failed_turn('RuntimeError: boom') }
    attempt = travel_to(2.minutes.ago) do
      ScanSolo::CadenceAttempt.create!(enrollment: enrollment, step: 1, cadence_version: 1, template_reference: 't1', scheduled_at: 1.hour.ago,
                                       result: :failed, external_error: 'meta error')
    end
    correlation_id = SecureRandom.uuid
    ScanSolo::MakeRequest.create!(account: account, correlation_id: correlation_id, idempotency_key: 'k', action: 'proposal.generate',
                                  payload: {}, status: :sent)
    callback = rejected_callback(correlation_id)

    errors = feed.recent_errors
    expect(errors.map { |error| [error.kind, error.id, error.reason] }).to eq(
      [['make_callback', callback.id, 'schema_invalid'], ['cadence_attempt', attempt.id, 'meta error'], ['ai_turn', turn.id, 'RuntimeError: boom']]
    )
    expect(errors.last.correlation_id).to eq(turn.correlation_id)
  end

  it 'caps recent errors at 100' do
    60.times { failed_turn('boom') }
    correlation_id = SecureRandom.uuid
    ScanSolo::MakeRequest.create!(account: account, correlation_id: correlation_id, idempotency_key: 'k', action: 'proposal.generate',
                                  payload: {}, status: :sent)
    60.times { rejected_callback(correlation_id) }

    expect(feed.recent_errors.length).to eq(100)
  end

  it "never includes another account's errors" do
    other_account = create(:account)
    other_conversation = create(:conversation, account: other_account)
    message = create(:message, account: other_account, conversation: other_conversation, message_type: :incoming)
    ScanSolo::AiTurn.create!(message: message, conversation: other_conversation, correlation_id: SecureRandom.uuid, invocation_status: :failed)

    expect(feed.recent_errors).to be_empty
  end
end
