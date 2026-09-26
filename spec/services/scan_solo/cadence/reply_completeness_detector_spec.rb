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

  before do
    draft = ScanSolo::AiAgentConfig.draft_for!(account)
    draft.update!(name: 'Agente', enabled: true, required_qualification_fields: %w[budget timeline])
    ScanSolo::AiAgent::PublishService.new(account: account).call
  end

  def call
    described_class.call(opportunity: opportunity)
  end

  describe 'full customer reply (all required fields satisfied)' do
    before { contact.update!(custom_attributes: { 'budget' => '1000', 'timeline' => '30 dias' }) }

    it 'stops/recalculates the full pending schedule' do
      result = call

      expect(result).to be_complete
      expect(result.missing_fields).to be_empty
      expect(enrollment.reload).to be_cancelled
      expect(enrollment.attempts.pluck(:result).uniq).to eq(['cancelled'])
    end
  end

  describe 'partial customer reply (at least one required field missing)' do
    before { contact.update!(custom_attributes: { 'budget' => '1000' }) }

    it 'cancels only the immediate pending send, leaving the rest of the schedule scheduled' do
      remaining_attempts = enrollment.attempts.order(:scheduled_at).drop(1)

      result = call

      expect(result).to be_partial
      expect(result.missing_fields).to eq(['timeline'])
      expect(enrollment.reload).to be_active

      first_attempt = enrollment.attempts.order(:scheduled_at).first
      expect(first_attempt).to be_cancelled
      remaining_attempts.each { |attempt| expect(attempt.reload).to be_scheduled }
    end
  end

  describe 'fields satisfied through native values and aliases (RF-13)' do
    let(:contact) { create(:contact, account: account, email: 'lead@example.com') }

    before do
      draft = ScanSolo::AiAgentConfig.draft_for!(account)
      draft.update!(required_qualification_fields: ['E-mail', 'Cidade / UF', 'Prazo desejado'])
      ScanSolo::AiAgent::PublishService.new(account: account).call
    end

    it 'is complete and cancels every scheduled attempt when the remaining fields are satisfied only via native/alias' do
      contact.update!(custom_attributes: { 'cidade_uf' => 'Rio/RJ', 'prazo' => 'amanhã' })

      result = call

      expect(result).to be_complete
      expect(enrollment.reload).to be_cancelled
      expect(enrollment.attempts.pluck(:result).uniq).to eq(['cancelled'])
    end

    it 'cancels only the earliest scheduled attempt when one field is still unsatisfied' do
      contact.update!(custom_attributes: { 'cidade' => 'Rio/RJ' })

      result = call

      expect(result.missing_fields).to eq(['Prazo desejado'])
      expect(enrollment.reload).to be_active
      expect(enrollment.attempts.order(:scheduled_at).map(&:result)).to eq(%w[cancelled scheduled scheduled])
    end
  end
end
