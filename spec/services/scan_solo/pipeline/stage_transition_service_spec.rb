# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Pipeline::StageTransitionService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:user) { create(:user, account: account) }

  let(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :novo_lead)
  end

  def call(target_stage:, actor: nil, authorized: false)
    described_class.new(opportunity: opportunity, target_stage: target_stage, actor: actor, authorized: authorized).call
  end

  it 'applies a valid transition and appends exactly one history row' do
    expect do
      call(target_stage: :em_contato, actor: user)
    end.to change(ScanSolo::PipelineStageEvent, :count).by(1)

    expect(opportunity.reload.stage).to eq('em_contato')

    event = opportunity.stage_events.last
    expect(event.from_stage).to eq('novo_lead')
    expect(event.to_stage).to eq('em_contato')
    expect(event.actor).to eq(user)
  end

  it 'rejects an out-of-vocabulary target stage, leaving the DB column unchanged' do
    expect do
      call(target_stage: 'inventado')
    end.to raise_error(ActiveRecord::RecordInvalid)

    expect(opportunity.reload.stage).to eq('novo_lead')
  end

  it 'does not create a history row for a rejected transition' do
    expect do
      call(target_stage: 'inventado')
    rescue ActiveRecord::RecordInvalid
      nil
    end.not_to change(ScanSolo::PipelineStageEvent, :count)
  end

  describe 'negociacao guard (RF-18)' do
    it 'rejects a non-authorized attempt to reach negociacao' do
      expect do
        call(target_stage: :negociacao, authorized: false)
      end.to raise_error(ActiveRecord::RecordInvalid)

      expect(opportunity.reload.stage).to eq('novo_lead')
    end

    it 'applies an explicitly authorized transition to negociacao' do
      call(target_stage: :negociacao, actor: user, authorized: true)

      expect(opportunity.reload.stage).to eq('negociacao')
    end
  end

  # Escalação comercial RF-11/RF-23: ganho/perdido end the escalated state.
  describe 'escalation mark' do
    let(:opportunity) do
      ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :proposta_enviada,
                                            escalated_to_commercial_at: 1.hour.ago, escalation_reason: 'negociacao')
    end

    before do
      ScanSolo::AuditLogger.record!(subject: opportunity, event_type: 'commercial.escalated', correlation_id: SecureRandom.uuid,
                                    payload: { reason: 'negociacao' })
    end

    %w[ganho perdido].each do |terminal|
      it "clears the mark on #{terminal} and keeps the commercial.escalated events" do
        call(target_stage: terminal)

        expect(opportunity.reload).to have_attributes(escalated_to_commercial_at: nil, escalation_reason: nil)
        expect(ScanSolo::AuditEvent.where(subject: opportunity, event_type: 'commercial.escalated').count).to eq(1)
      end
    end

    it 'keeps the mark on a non-terminal move' do
      call(target_stage: :negociacao, authorized: true)

      expect(opportunity.reload).to have_attributes(escalation_reason: 'negociacao', escalated_to_commercial_at: be_present)
    end
  end

  describe 'terminal stages (RF-19)' do
    %w[ganho perdido].each do |terminal_stage|
      it "rejects any further transition once the opportunity is #{terminal_stage}" do
        opportunity.update!(stage: terminal_stage)

        expect do
          call(target_stage: :em_contato, actor: user, authorized: true)
        end.to raise_error(ActiveRecord::RecordInvalid)

        expect(opportunity.reload.stage).to eq(terminal_stage)
      end
    end
  end
end
