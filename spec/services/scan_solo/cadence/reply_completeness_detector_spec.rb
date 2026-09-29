# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Cadence::ReplyCompletenessDetector do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :em_qualificacao)
  end
  let(:cadence_definition) { ScanSolo::CadenceDefinition.create!(stage: 'em_qualificacao', version: 1, offsets: [24, 48, 72]) }
  let!(:enrollment) do
    ScanSolo::Cadence::EnrollmentService.call(opportunity: opportunity, cadence_definition: cadence_definition)
  end

  let(:writer) { ScanSolo::LeadState::Writer.new(lead_state: opportunity.lead_state) }

  before do
    draft = ScanSolo::AiAgentConfig.draft_for!(account)
    draft.update!(name: 'Agente', enabled: true, required_qualification_fields: ['Área', 'Prazo desejado'])
    ScanSolo::AiAgent::PublishService.new(account: account).call
  end

  def call
    described_class.call(opportunity: opportunity)
  end

  describe 'full customer reply (all required fields confirmed in the lead state)' do
    before do
      writer.apply_field!(key: 'area', value: '800 m²', status: 'confirmado', source_message_id: nil)
      writer.apply_field!(key: 'prazo_desejado', value: '30 dias', status: 'confirmado', source_message_id: nil)
    end

    it 'stops/recalculates the full pending schedule' do
      result = call

      expect(result).to be_complete
      expect(result.missing_fields).to be_empty
      expect(enrollment.reload).to be_cancelled
      expect(enrollment.attempts.pluck(:result).uniq).to eq(['cancelled'])
    end
  end

  describe 'partial customer reply (at least one required field not confirmed)' do
    before { writer.apply_field!(key: 'area', value: '800 m²', status: 'confirmado', source_message_id: nil) }

    it 'cancels only the immediate pending send, leaving the rest of the schedule scheduled' do
      remaining_attempts = enrollment.attempts.order(:scheduled_at).drop(1)

      result = call

      expect(result).to be_partial
      expect(result.missing_fields).to eq(['Prazo desejado'])
      expect(enrollment.reload).to be_active

      first_attempt = enrollment.attempts.order(:scheduled_at).first
      expect(first_attempt).to be_cancelled
      remaining_attempts.each { |attempt| expect(attempt.reload).to be_scheduled }
    end
  end

  describe 'satisfied = confirmado in the lead state (lead state RF-08)' do
    it 'keeps a field that is only in the Contact or only inferido as missing' do
      contact.update!(custom_attributes: { 'prazo' => 'amanhã' })
      writer.apply_field!(key: 'area', value: '800 m²', status: 'inferido', source_message_id: nil)

      result = call

      expect(result.missing_fields).to eq(['Área', 'Prazo desejado'])
      expect(enrollment.reload).to be_active
      expect(enrollment.attempts.order(:scheduled_at).map(&:result)).to eq(%w[cancelled scheduled scheduled])
    end
  end
end
