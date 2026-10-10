# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Quote::ResendService do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:customer_inbox) { create(:inbox, account: account) }
  let(:email_inbox) { create(:channel_email, account: account, email: 'atendimento.comercial@scansolo.com.br').inbox }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: customer_inbox, contact: contact) }
  let(:opportunity) { ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :qualificado) }
  let(:writer) { ScanSolo::LeadState::Writer.new(lead_state: opportunity.lead_state) }
  let(:draft) { ScanSolo::AiAgentConfig.draft_for!(account) }
  let(:notices) { conversation.messages.where("additional_attributes ->> 'scansolo_origin' = 'quote_notice'") }

  # RNF-04: 0 real SMTP (see spec/services/scan_solo/quote/email_thread_spec.rb).
  around do |example|
    original = ActionMailer::Base.delivery_method
    ActionMailer::Base.delivery_method = :test
    example.run
  ensure
    ActionMailer::Base.delivery_method = original
  end

  before do
    allow(ChatwootExceptionTracker).to receive(:new).and_call_original
    republish!(name: 'Agente', enabled: true, allowed_inbox_ids: [customer_inbox.id], quote_inbox_id: email_inbox.id)
    writer.complete!(at: Time.current)
    writer.record_next_action!(value: 'proposta', source_message_id: nil)
  end

  def republish!(**attributes)
    draft.update!(attributes)
    ScanSolo::AiAgent::PublishService.new(account: account).call
  end

  def misconfigured_dispatch!
    republish!(quote_inbox_id: nil)
    ScanSolo::Quote::RequestService.call(opportunity: opportunity)
    republish!(quote_inbox_id: email_inbox.id)
  end

  def resend
    described_class.call(opportunity: ScanSolo::PipelineOpportunity.find(opportunity.id), actor: admin)
  end

  it 'creates one request for two concurrent resends without a request (RF-15, RNF-02)' do
    misconfigured_dispatch!

    Array.new(2) { Thread.new { resend } }.each(&:join)

    expect(ScanSolo::QuoteRequest.where(opportunity: opportunity).count).to eq(1)
    expect(notices.count).to eq(1)
  end

  it 'keeps a single notice when resending a request that already had one (RF-53)' do
    ScanSolo::Quote::RequestService.call(opportunity: opportunity)
    expect(notices.count).to eq(1)

    2.times { resend }

    expect(notices.count).to eq(1)
    expect(ScanSolo::QuoteRequest.sole.email_conversation.messages.outgoing.count).to eq(3)
  end

  # RF-20 (replaces the OC/RF-13 body expectations): the resend renders the CT-01 e-mail from the current data.
  describe 'resend in the CT-01 format (RF-20)' do
    let(:quote_request) { ScanSolo::QuoteRequest.sole }
    let(:outgoing) { quote_request.email_conversation.messages.outgoing }

    before do
      ScanSolo::Quote::RequestService.call(opportunity: opportunity)
      writer.apply_field!(key: 'profundidade', value: '3 m', status: 'confirmado', source_message_id: nil)
    end

    it 'posts 2 messages in the same thread, with 1 request, no new notice and no update e-mail' do
      expect { 2.times { resend } }.to change(outgoing, :count).by(2)

      expect(outgoing.order(:id).last.content).to include('DADOS DO CLIENTE', 'Profundidade de interesse: 3 m')
      expect(outgoing.order(:id).last.additional_attributes).to include('scansolo_origin' => 'quote_request_email')
      expect(ScanSolo::QuoteRequest.where(opportunity: opportunity).count).to eq(1)
      expect(notices.count).to eq(1)
      expect(ScanSolo::QuoteRequestUpdate.count).to eq(0)
    end

    it 'makes the last resend the base of the next update and audits each one as quote_request.sent' do
      2.times { resend }

      snapshot = ScanSolo::Quote::RequestEmail::Snapshot.call(opportunity: opportunity, config: ScanSolo::AiAgentConfig.published_for(account))
      expect(quote_request).to have_attributes(
        request_message_id: outgoing.order(:id).last.id, rendered_snapshot: snapshot, rendered_digest: Digest::SHA256.hexdigest(snapshot.to_json)
      )
      expect(snapshot.dig('fields', 'profundidade', 'value')).to eq('3 m')
      expect(ScanSolo::AuditEvent.where(event_type: 'quote_request.sent', correlation_id: quote_request.correlation_id).count).to eq(3)
    end
  end

  it 'keeps a correction_requested request status' do
    ScanSolo::Quote::RequestService.call(opportunity: opportunity)
    ScanSolo::QuoteRequest.sole.update!(status: :correction_requested)

    expect(resend.quote_request.reload).to be_correction_requested
  end

  describe '.available?' do
    it 'is true for an open request' do
      ScanSolo::Quote::RequestService.call(opportunity: opportunity)

      expect(described_class.available?(opportunity.reload)).to be(true)
    end

    it 'is false for a replied request' do
      ScanSolo::Quote::RequestService.call(opportunity: opportunity)
      opportunity.quote_request.update!(status: :replied)

      expect(described_class.available?(opportunity.reload)).to be(false)
    end

    it 'is true without a request after a misconfigured dispatch' do
      misconfigured_dispatch!

      expect(described_class.available?(opportunity.reload)).to be(true)
    end

    it 'is false without a request nor misconfigured audit' do
      expect(described_class.available?(opportunity)).to be(false)
    end
  end
end
