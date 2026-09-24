# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Messaging::TemplateResolver do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:contact) { create(:contact, account: account, name: 'Maria Souza') }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :em_contato)
  end

  before do
    ScanSolo::CadenceDefinition.create!(stage: 'em_contato', version: 2, offsets: [24, 48])
    ScanSolo::AiAgentConfig.draft_for!(account).update!(name: 'Ana', enabled: true)
    ScanSolo::AiAgent::PublishService.new(account: account).call
  end

  describe 'a mapped step' do
    before do
      ScanSolo::TemplateMapping.create!(
        account: account, stage: 'em_contato', step: 2, template_name: 'scansolo_followup_contato', language: 'pt_BR',
        params: [
          { 'source' => 'contact_first_name' }, { 'source' => 'contact_name' }, { 'source' => 'agent_name' },
          { 'source' => 'stage_label' }, { 'source' => 'static', 'value' => 'ScanSolo' }
        ]
      )
    end

    it 'resolves the mapped name, language and every allowlisted source into native processed params' do
      template = described_class.call(account: account, stage: 'em_contato', step: 2, opportunity: opportunity)

      expect(template).to be_mapped
      expect(template.name).to eq('scansolo_followup_contato')
      expect(template.language).to eq('pt_BR')
      expect(template.processed_params).to eq(
        'body' => { '1' => 'Maria', '2' => 'Maria Souza', '3' => 'Ana', '4' => 'Em Contato', '5' => 'ScanSolo' }
      )
    end

    it 'sends the resolved template_params through the native message create path' do
      template = described_class.call(account: account, stage: 'em_contato', step: 2, opportunity: opportunity)

      message = ScanSolo::Messaging::NativeTemplateSender.call(
        conversation: conversation, template_reference: template.name, template_params: template.sender_params, origin: 'cadence'
      ).message

      expect(message.additional_attributes['template_params']).to eq(
        'name' => 'scansolo_followup_contato', 'language' => 'pt_BR',
        'processed_params' => { 'body' => { '1' => 'Maria', '2' => 'Maria Souza', '3' => 'Ana', '4' => 'Em Contato', '5' => 'ScanSolo' } }
      )
    end
  end

  describe 'an unmapped step' do
    it 'falls back to the naming convention in pt_BR without params' do
      template = described_class.call(account: account, stage: 'em_contato', step: 1, opportunity: opportunity)

      expect(template).not_to be_mapped
      expect(template.name).to eq('scansolo_cadence_em_contato_v2_step1')
      expect(template.language).to eq('pt_BR')
      expect(template.params).to eq([])
      expect(template.processed_params).to eq({})
    end

    it 'uses the proposal send default for the proposal row (step nil)' do
      template = described_class.definition_for(account: account, stage: 'proposta_enviada', step: nil)

      expect(template.name).to eq('scansolo_proposal_send')
      expect(template.language).to eq('pt_BR')
    end
  end

  it 'ignores mappings of another account' do
    other_account = create(:account)
    ScanSolo::TemplateMapping.create!(account: other_account, stage: 'em_contato', step: 1, template_name: 'other', language: 'en', params: [])

    expect(described_class.definition_for(account: account, stage: 'em_contato', step: 1).name).to eq('scansolo_cadence_em_contato_v2_step1')
  end
end
