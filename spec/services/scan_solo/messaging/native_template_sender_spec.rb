# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Messaging::NativeTemplateSender do
  let(:account) { create(:account) }

  def call(conversation:, template_reference: 'scansolo_cadence_novo_lead_v1_step1', template_params: {}, actor: nil)
    described_class.call(conversation: conversation, template_reference: template_reference, origin: 'cadence',
                         template_params: template_params, actor: actor)
  end

  describe 'native message-create path (RF-70)' do
    let(:contact) { create(:contact, account: account) }
    let(:conversation) { create(:conversation, account: account, contact: contact) }

    it 'creates the outbound message through conversation.messages.create! using the documented template_params shape' do
      result = perform_enqueued_jobs { call(conversation: conversation, template_params: { category: 'UTILITY', language: 'pt_BR' }) }

      expect(result.message).to be_persisted
      expect(result.message).to be_outgoing
      expect(result.message.conversation_id).to eq(conversation.id)
      expect(result.message.additional_attributes['template_params']).to eq(
        'name' => 'scansolo_cadence_novo_lead_v1_step1',
        'category' => 'UTILITY',
        'language' => 'pt_BR',
        'processed_params' => {}
      )
    end

    it 'makes zero calls to a real Meta endpoint for a fake template reference on a non-WhatsApp channel' do
      expect do
        perform_enqueued_jobs { call(conversation: conversation, template_reference: 'totally_fake_template') }
      end.not_to raise_error

      expect(a_request(:post, %r{waba\.360dialog\.io})).not_to have_been_made
    end
  end

  describe 'transport acceptance/rejection (RF-72)' do
    before { stub_request(:post, 'https://waba.360dialog.io/v1/configs/webhook') }

    let!(:whatsapp_channel) { create(:channel_whatsapp, sync_templates: false) }
    let!(:contact_inbox) { create(:contact_inbox, inbox: whatsapp_channel.inbox, source_id: '123456789') }
    let!(:conversation) { create(:conversation, contact_inbox: contact_inbox, inbox: whatsapp_channel.inbox, account: whatsapp_channel.account) }

    it 'leaves the evidence record non-sent when the native transport rejects the send' do
      stub_request(:post, 'https://waba.360dialog.io/v1/messages').to_return(
        status: 500,
        body: { meta: { success: false, http_code: 500, developer_message: 'rejected' } }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

      result = perform_enqueued_jobs do
        call(conversation: conversation, template_reference: 'sample_shipping_confirmation',
             template_params: { namespace: '23423423_2342423_324234234_2343224', language: 'en_US', category: 'Marketing' })
      end

      expect(result.message.reload.status).to eq('failed')
    end

    it 'captures a later delivery-status update on the same record, never a duplicate one' do
      stub_request(:post, 'https://waba.360dialog.io/v1/messages').to_return(status: 200, body: { messages: [{ id: 'wamid.123' }] }.to_json)

      result = perform_enqueued_jobs do
        call(conversation: conversation, template_reference: 'sample_shipping_confirmation',
             template_params: { namespace: '23423423_2342423_324234234_2343224', language: 'en_US', category: 'Marketing' })
      end

      message = result.message.reload
      expect(message.status).not_to eq('failed')

      # A native delivery-status webhook updates the same Message row directly.
      message.update!(status: :delivered)

      expect(Message.where(conversation_id: conversation.id).count).to eq(1)
      expect(message.reload.status).to eq('delivered')
    end
  end
end
