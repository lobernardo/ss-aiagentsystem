# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Proposal::SuccessHandler do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :qualificado)
  end
  let(:proposal) { ScanSolo::Proposal.create!(opportunity: opportunity) }
  let!(:cadence_definition) { ScanSolo::CadenceDefinition.create!(stage: 'proposta_enviada', version: 1, offsets: [24, 72, 168]) }

  def call(version)
    described_class.call(proposal_version: version)
  end

  it 'transitions the opportunity to proposta_enviada (RF-17)' do
    version = proposal.versions.create!(status: :sent, value: 1000, currency: 'BRL')

    call(version)

    expect(opportunity.reload).to be_proposta_enviada
  end

  it 'enrolls the opportunity in the configured post-proposal cadence (RF-82)' do
    version = proposal.versions.create!(status: :sent, value: 1000, currency: 'BRL')

    call(version)

    enrollment = opportunity.cadence_enrollments.active.sole
    expect(enrollment.cadence_definition).to eq(cadence_definition)
    expect(enrollment.attempts.count).to eq(3)
  end

  it 'is a no-op on a terminal (ganho/perdido) opportunity, leaving stage and cadence untouched (RF-19)' do
    opportunity.update!(stage: :ganho)
    version = proposal.versions.create!(status: :sent, value: 1000, currency: 'BRL')

    call(version)

    expect(opportunity.reload).to be_ganho
    expect(opportunity.cadence_enrollments.active).to be_none
  end

  it 'does not duplicate the transition or enrollment when called twice' do
    version = proposal.versions.create!(status: :sent, value: 1000, currency: 'BRL')

    call(version)
    call(version)

    expect(opportunity.reload).to be_proposta_enviada
    expect(opportunity.cadence_enrollments.active.count).to eq(1)
  end
end
