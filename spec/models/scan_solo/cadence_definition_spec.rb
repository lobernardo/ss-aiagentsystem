# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::CadenceDefinition do
  before do
    load Rails.root.join('db/seeds/scansolo_cadence_definitions.rb')
  end

  describe 'seeded schedules (RF-57)' do
    it 'schedules exactly 4 attempts at +2h/+24h/+48h/+96h for Novo Lead' do
      definition = described_class.current_for('novo_lead')

      expect(definition.attempt_count).to eq(4)
      expect(definition.offsets).to eq([2, 24, 48, 96])
    end

    it 'schedules exactly 5 attempts 24h apart for Em Contato' do
      definition = described_class.current_for('em_contato')

      expect(definition.attempt_count).to eq(5)
      expect(definition.offsets).to eq([24, 48, 72, 96, 120])
    end

    it 'schedules exactly 4 attempts at +24h/+48h/+96h/+168h for Em Qualificação (v2, DEC-038)' do
      definition = described_class.current_for('em_qualificacao')

      expect(definition.attempt_count).to eq(4)
      expect(definition.offsets).to eq([24, 48, 96, 168])
      expect(definition.version).to eq(2)
    end
  end

  describe '#template_reference_for' do
    it 'derives a deterministic, fake-safe template reference per step (RF-71)' do
      definition = described_class.current_for('novo_lead')

      expect(definition.template_reference_for(1)).to eq("scansolo_cadence_novo_lead_v#{definition.version}_step1")
    end
  end

  describe 'enrolling a fixture opportunity in each stage cadence' do
    let(:account) { create(:account) }
    let(:contact) { create(:contact, account: account) }
    let(:conversation) { create(:conversation, account: account, contact: contact) }
    let(:opportunity) do
      ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :novo_lead)
    end

    it 'schedules exactly the configured attempt count/offsets for the stage' do
      definition = described_class.current_for('novo_lead')
      enrollment = ScanSolo::CadenceEnrollment.create!(opportunity: opportunity, cadence_definition: definition)
      enrolled_at = enrollment.created_at

      definition.offsets.each_with_index do |offset_hours, index|
        enrollment.attempts.create!(
          step: index + 1,
          cadence_version: definition.version,
          template_reference: definition.template_reference_for(index + 1),
          scheduled_at: enrolled_at + offset_hours.hours
        )
      end

      expect(enrollment.attempts.count).to eq(4)
      expect(enrollment.attempts.order(:step).pluck(:scheduled_at)).to eq(
        [2, 24, 48, 96].map { |hours| enrolled_at + hours.hours }
      )
    end
  end
end
