# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Actions::StageTransitionAction do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :em_qualificacao)
  end

  def call(target_stage)
    described_class.call(params: { opportunity_id: opportunity.id, target_stage: target_stage })
  end

  describe 'RF-14: forbidden AI targets' do
    %w[negociacao ganho perdido proposta_enviada em_contato].each do |target|
      it "rejects #{target} without changing the stage" do
        result = call(target)

        expect(result).to eq(status: 'rejected', reason: 'stage_not_allowed_for_ai', from_stage: 'em_qualificacao', target_stage: target)
        expect(opportunity.reload).to be_em_qualificacao
        expect(opportunity.stage_events).to be_none
      end
    end
  end

  it 'moves em_contato forward to em_qualificacao with a PipelineStageEvent' do
    opportunity.update!(stage: :em_contato)

    result = call('em_qualificacao')

    expect(result).to eq(status: 'transitioned', from_stage: 'em_contato', to_stage: 'em_qualificacao')
    expect(opportunity.reload).to be_em_qualificacao
    expect(opportunity.stage_events.sole).to have_attributes(from_stage: 'em_contato', to_stage: 'em_qualificacao')
  end

  it 'moves forward to qualificado' do
    expect(call('qualificado')[:status]).to eq('transitioned')
    expect(opportunity.reload).to be_qualificado
  end

  it 'no longer accepts the authorized flag through its schema' do
    expect(described_class::SCHEMA['properties']).not_to have_key('authorized')
  end
end
