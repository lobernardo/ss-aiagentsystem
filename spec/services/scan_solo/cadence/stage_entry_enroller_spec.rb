# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Cadence::StageEntryEnroller do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :novo_lead)
  end

  describe 'RF-24: each enrolling stage entry creates one active enrollment for its current definition' do
    before do
      { 'novo_lead' => [2, 24, 48, 96], 'em_contato' => [24, 48, 72, 96, 120],
        'em_qualificacao' => [24, 48, 72, 96, 120, 144, 168], 'proposta_enviada' => [24, 72, 168] }.each do |stage, offsets|
        ScanSolo::CadenceDefinition.create!(stage: stage, version: 1, offsets: offsets)
      end
    end

    it 'enrolls a novo_lead opportunity on entry' do
      described_class.call(opportunity: opportunity)

      expect(opportunity.cadence_enrollments.active.sole.cadence_definition.stage).to eq('novo_lead')
    end

    %w[em_contato em_qualificacao proposta_enviada].each do |stage|
      it "enrolls through StageTransitionService when entering #{stage}" do
        ScanSolo::Pipeline::StageTransitionService.new(opportunity: opportunity, target_stage: stage).call

        active = opportunity.cadence_enrollments.active
        expect(active.count).to eq(1)
        expect(active.sole.cadence_definition).to eq(ScanSolo::CadenceDefinition.current_for(stage))
      end
    end

    it 'does not enroll a stage without a cadence (qualificado)' do
      ScanSolo::Pipeline::StageTransitionService.new(opportunity: opportunity, target_stage: :qualificado).call

      expect(opportunity.cadence_enrollments.active).to be_none
    end

    it 'skips an opted-out contact (RF-31)' do
      ScanSolo::ContactExtension.resolve_for(contact).update!(opted_out: true)

      expect(described_class.call(opportunity: opportunity)).to be_nil
      expect(opportunity.cadence_enrollments).to be_none
    end
  end

  describe 'RF-24: missing definition fails loudly' do
    it 'reports the misconfiguration to the tracker and records one audit event' do
      tracker = instance_double(ChatwootExceptionTracker, capture_exception: nil)
      allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)

      described_class.call(opportunity: opportunity)

      expect(ChatwootExceptionTracker).to have_received(:new)
        .with(an_object_having_attributes(class: CustomExceptions::ScanSolo::CadenceDefinitionMissing), account: account)
      expect(tracker).to have_received(:capture_exception).once
      expect(ScanSolo::AuditEvent.where(event_type: 'cadence.definition_missing', subject: opportunity).count).to eq(1)
      expect(opportunity.cadence_enrollments).to be_none
    end
  end
end
