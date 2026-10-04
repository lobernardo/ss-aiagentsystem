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
