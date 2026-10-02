# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Pipeline::ManualLeadOutreach do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:message_templates) do
    [{ 'name' => 'scansolo_ola_comercial', 'status' => 'APPROVED', 'language' => 'pt_BR', 'category' => 'UTILITY',
       'components' => [{ 'type' => 'BODY', 'text' => 'Olá {{1}}, aqui é da ScanSolo.' }] }]
  end
  let(:channel) { create(:channel_whatsapp, account: account, sync_templates: false, message_templates: message_templates) }
  let(:inbox) { channel.inbox }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:params) do
    { account: account, actor: admin, name: 'Ana Souza', phone_number: '+5511987654321', email: nil, company: nil,
      owner_id: nil, inbox: inbox }
  end
  let(:template_messages) { Message.where("additional_attributes->>'scansolo_origin' = 'manual_lead'") }

  before do
    stub_request(:post, 'https://waba.360dialog.io/v1/configs/webhook')
    ScanSolo::CadenceDefinition.create!(stage: 'novo_lead', version: 1, offsets: [2, 24, 48, 96])
    ScanSolo::AiAgentConfig.draft_for!(account).update!(name: 'Agente', enabled: true, allowed_inbox_ids: [inbox.id])
    ScanSolo::AiAgent::PublishService.new(account: account).call
    ScanSolo::TemplateMapping.create!(account: account, stage: 'lead_manual_inicial', step: nil, template_name: 'scansolo_ola_comercial',
                                      language: 'pt_BR', params: [{ 'source' => 'contact_first_name' }])
    inbox
    WebMock.reset_executed_requests!
  end

  describe 'guard available (RF-07)' do
    it 'creates one native outgoing template message marked manual_lead with the mapped name and no direct HTTP' do
      opportunity = ScanSolo::Pipeline::ManualLeadService.call(**params).opportunity

      expect(template_messages.count).to eq(1)
      message = template_messages.first
      expect(message).to have_attributes(conversation_id: opportunity.conversation_id, message_type: 'outgoing', sender: nil)
      expect(message.additional_attributes['template_params']).to include(
        'name' => 'scansolo_ola_comercial', 'language' => 'pt_BR', 'processed_params' => { 'body' => { '1' => 'Ana' } }
      )
      expect(a_request(:any, /.*/)).not_to have_been_made
    end

    it 'keeps the AI active when the template message goes through the native listener' do
      opportunity = ScanSolo::Pipeline::ManualLeadService.call(**params).opportunity

      ScanSolo::ConversationListener.instance.message_created(
        Events::Base.new('message_created', Time.zone.now, { message: template_messages.first })
      )

      expect(ScanSolo::ConversationExtension.resolve_for(opportunity.conversation)).to be_ai_active
    end

    it 'sends only after every transaction of the registration committed (RNF-01)' do
      baseline = ActiveRecord::Base.connection.open_transactions
      open_at_send = nil
      allow(ScanSolo::Messaging::NativeTemplateSender).to receive(:call).and_wrap_original do |original, **kwargs|
        open_at_send = ActiveRecord::Base.connection.open_transactions
        original.call(**kwargs)
      end

      ScanSolo::Pipeline::ManualLeadService.call(**params)

      expect(ScanSolo::Messaging::NativeTemplateSender).to have_received(:call).once
      expect(open_at_send).to eq(baseline)
    end
  end

  describe 'guard blocked (RF-08)' do
    let(:message_templates) { [] }

    it 'sends no message and records one audit with the block reason' do
      opportunity = ScanSolo::Pipeline::ManualLeadService.call(**params).opportunity

      expect(template_messages.count).to eq(0)
      audits = ScanSolo::AuditEvent.where(subject: opportunity, event_type: 'pipeline.manual_lead_template_blocked')
      expect(audits.count).to eq(1)
      expect(audits.first.payload).to eq('reason' => 'template_missing')
    end
  end
end
