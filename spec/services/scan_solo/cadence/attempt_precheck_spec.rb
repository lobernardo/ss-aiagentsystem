# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Cadence::AttemptPrecheck do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :novo_lead)
  end
  let(:cadence_definition) { ScanSolo::CadenceDefinition.create!(stage: 'novo_lead', version: 1, offsets: [2]) }
  let(:attempt) { ScanSolo::Cadence::EnrollmentService.call(opportunity: opportunity, cadence_definition: cadence_definition).attempts.first }
  let(:draft) { ScanSolo::AiAgentConfig.draft_for!(account) }

  before do
    stub_request(:post, 'https://waba.360dialog.io/v1/configs/webhook')
    draft.update!(name: 'Agente', enabled: true, allowed_inbox_ids: [inbox.id])
    ScanSolo::AiAgent::PublishService.new(account: account).call
  end

  def precheck
    described_class.call(attempt: attempt)
  end

  it 'sends with the resolved template when every check passes' do
    result = precheck

    expect(result).to be_send
    expect(result.template.name).to eq('scansolo_cadence_novo_lead_v1_step1')
  end

  it 'defers first on the account kill switch, even for an opted-out contact (RF-04)' do
    ScanSolo::ContactExtension.resolve_for(contact).update!(opted_out: true)
    account.update!(scansolo_enabled: false)

    expect(precheck).to have_attributes(decision: :defer, reason: 'scansolo_disabled')
  end

  it '(1) cancels when the contact opted out' do
    ScanSolo::ContactExtension.resolve_for(contact).update!(opted_out: true)

    expect(precheck).to have_attributes(decision: :cancel, reason: 'opt_out')
  end

  it '(2) cancels when the conversation is resolved' do
    conversation.update!(status: :resolved)

    expect(precheck).to have_attributes(decision: :cancel, reason: 'conversation_resolved')
  end

  describe '(3) eligibility and AI control' do
    it 'defers when the published config is disabled' do
      draft.update!(enabled: false)
      ScanSolo::AiAgent::PublishService.new(account: account).call

      expect(precheck).to have_attributes(decision: :defer, reason: 'config_unavailable')
    end

    it 'defers when the inbox is not allowlisted' do
      draft.update!(allowed_inbox_ids: [])
      ScanSolo::AiAgent::PublishService.new(account: account).call

      expect(precheck).to have_attributes(decision: :defer, reason: 'inbox_not_allowlisted')
    end

    it 'defers when the inbox has an active bot' do
      create(:agent_bot_inbox, inbox: inbox, status: :active)

      expect(precheck).to have_attributes(decision: :defer, reason: 'inbox_has_active_bot')
    end

    it 'defers while a human controls the conversation' do
      ScanSolo::ConversationExtension.resolve_for(conversation).update!(ai_control_state: :human_active)

      expect(precheck).to have_attributes(decision: :defer, reason: 'human_controlled')
    end
  end

  describe '(4) template availability' do
    let(:channel) do
      create(:channel_whatsapp, account: account, sync_templates: false, message_templates: [
               { 'name' => 'scansolo_cadence_novo_lead_v1_step1', 'status' => 'PAUSED', 'language' => 'pt_BR',
                 'components' => [{ 'type' => 'BODY', 'text' => 'Oi' }] }
             ])
    end
    let(:inbox) { channel.inbox }
    let(:contact_inbox) { create(:contact_inbox, inbox: inbox, contact: contact, source_id: '5511988887777') }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }

    it 'defers with the guard reason' do
      expect(precheck).to have_attributes(decision: :defer, reason: 'template_paused')
    end
  end
end
