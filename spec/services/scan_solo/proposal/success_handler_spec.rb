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

  it 'sends the post-proposal follow-up once, after the commit (RF-31)' do
    version = proposal.versions.create!(status: :sent, value: 1000, currency: 'BRL')
    follow_ups = conversation.messages.where("additional_attributes ->> 'scansolo_origin' = 'proposal_follow_up'")

    ActiveRecord::Base.transaction do
      call(version)
      expect(follow_ups.count).to eq(0)
    end
    call(version)

    expect(follow_ups.count).to eq(1)
    expect(version.reload.follow_up_message).to eq(follow_ups.sole)
  end

  it 'sends one e-mail notice and then one follow-up, both after the commit (RF-11, RF-13, RF-31)' do
    version = proposal.versions.create!(status: :sent, value: 1000, currency: 'BRL')
    notices = conversation.messages.where("additional_attributes ->> 'scansolo_origin' = 'proposal_notice'")
    follow_ups = conversation.messages.where("additional_attributes ->> 'scansolo_origin' = 'proposal_follow_up'")

    ActiveRecord::Base.transaction do
      call(version)
      expect(notices.count + follow_ups.count).to eq(0)
    end

    expect(notices.count).to eq(1)
    expect(follow_ups.count).to eq(1)
    expect(notices.sole.id).to be < follow_ups.sole.id
    expect(version.reload).to have_attributes(notice_message: notices.sole, follow_up_message: follow_ups.sole)
  end

  it 'sends no notice nor follow-up for a version that is not sent (RF-12)' do
    version = proposal.versions.create!(status: :approved, value: 1000, currency: 'BRL')

    call(version)

    expect(conversation.messages.count).to eq(0)
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
