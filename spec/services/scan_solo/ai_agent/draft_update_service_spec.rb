# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::AiAgent::DraftUpdateService do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:draft) { ScanSolo::AiAgentConfig.draft_for!(account) }

  it 'updates the draft and records one audit event with actor, subject and correlation id' do
    expect do
      described_class.call(draft: draft, actor: admin, attributes: { name: 'Agente', tone: 'cordial' })
    end.to change(ScanSolo::AuditEvent, :count).by(1)

    expect(draft.reload).to have_attributes(name: 'Agente', tone: 'cordial')
    event = ScanSolo::AuditEvent.last
    expect(event).to have_attributes(event_type: 'ai_agent_config.draft_updated', subject: draft, actor: admin)
    expect(event.correlation_id).to be_present
    expect(event.payload).to include('changed_fields' => match_array(%w[name tone]), 'opt_out_keywords_changed' => false)
  end

  it 'flags an opt-out keyword list change (RF-16)' do
    described_class.call(draft: draft, actor: admin, attributes: { opt_out_keywords: %w[PARAR SAIR STOP CANCELAR] })

    expect(draft.reload.opt_out_keywords).to include('CANCELAR')
    expect(ScanSolo::AuditEvent.last.payload).to include('opt_out_keywords_changed' => true)
  end

  it 'never stores field values in the audit payload' do
    described_class.call(draft: draft, actor: admin, attributes: { instructions: 'sk-proj-secret-value-that-must-not-leak' })

    expect(ScanSolo::AuditEvent.last.payload.to_json).not_to include('sk-proj-secret')
  end

  it 'records nothing when the update is invalid' do
    expect do
      described_class.call(draft: draft, actor: admin, attributes: { name: 'x' * 10_000, status: :bogus })
    rescue ArgumentError, ActiveRecord::RecordInvalid
      nil
    end.not_to change(ScanSolo::AuditEvent, :count)
  end
end
