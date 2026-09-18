# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Actions::QualificationFieldAction do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }

  let!(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :em_contato)
  end

  before do
    draft = ScanSolo::AiAgentConfig.draft_for!(account)
    draft.update!(name: 'Agente', enabled: true, required_qualification_fields: %w[budget timeline])
    ScanSolo::AiAgent::PublishService.new(account: account).call
  end

  def call(fields:)
    described_class.call(params: { conversation_id: conversation.id, fields: fields })
  end

  describe 'RF-15: qualification interaction begins' do
    it 'moves an em_contato opportunity to em_qualificacao exactly once' do
      call(fields: { budget: '1000' })

      expect(opportunity.reload.stage).to eq('em_qualificacao')

      # A second invocation (still missing the "timeline" field) must not
      # re-trigger the em_contato -> em_qualificacao rule.
      expect(opportunity.stage_events.count).to eq(1)
      call(fields: { budget: '2000' })
      expect(opportunity.reload.stage).to eq('em_qualificacao')
      expect(opportunity.stage_events.count).to eq(1)
    end
  end

  describe 'RF-16: all required qualification fields satisfied' do
    before { opportunity.update!(stage: :em_qualificacao) }

    it 'auto-transitions to qualificado once every required field is satisfied' do
      call(fields: { budget: '1000', timeline: '30 dias' })

      expect(opportunity.reload.stage).to eq('qualificado')
    end

    it 'leaves the stage unchanged when one required field is still missing' do
      call(fields: { budget: '1000' })

      expect(opportunity.reload.stage).to eq('em_qualificacao')
    end
  end

  describe 'allowed-fields filtering (RF-48)' do
    before { opportunity.update!(stage: :em_qualificacao) }

    it 'only persists fields present in the published required_qualification_fields allowlist' do
      call(fields: { budget: '1000', not_allowed: 'ignored' })

      expect(contact.reload.custom_attributes['budget']).to eq('1000')
      expect(contact.reload.custom_attributes).not_to have_key('not_allowed')
    end
  end
end
