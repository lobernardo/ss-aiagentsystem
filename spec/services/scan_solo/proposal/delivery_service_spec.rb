# frozen_string_literal: true

require 'rails_helper'

# RF-11 replaces the OC/RF-29 / CT-10 expectations: an approved proposal goes to the lead by e-mail (CC comercial@,
# PDF attached) through the quote inbox -- no WhatsApp document, no Make request.
RSpec.describe ScanSolo::Proposal::DeliveryService do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:customer_inbox) { create(:inbox, account: account) }
  let(:email_inbox) do
    create(:channel_email, account: account, email: 'atendimento.comercial@scansolo.com.br', smtp_enabled: true,
                           smtp_address: 'smtp.example.com', smtp_port: 587, smtp_login: 'login', smtp_password: 'secret').inbox
  end
  let(:contact) { create(:contact, account: account, name: 'Ana Souza', email: 'ana@solar.example') }
  let(:conversation) { create(:conversation, account: account, inbox: customer_inbox, contact: contact) }
  let(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :qualificado)
  end
  let(:quote_request) do
    ScanSolo::QuoteRequest.create!(account: account, opportunity: opportunity, correlation_id: SecureRandom.uuid, status: :replied,
                                   commercial: { 'total_value' => '12500.00' })
  end
  let(:proposal) { ScanSolo::Proposal.create!(opportunity: opportunity) }
  let(:artifact_url) { 'https://make.example/proposals/7.pdf' }
  let(:version) { create_version }
  let(:email_messages) { Message.where(inbox: email_inbox).outgoing }
  let(:transaction_open_at) { [] }

  # RNF-04: 0 real SMTP -- the channel SMTP settings only enable the mailer; delivery stays on ActionMailer :test.
  around do |example|
    original = ActionMailer::Base.delivery_method
    ActionMailer::Base.delivery_method = :test
    example.run
  ensure
    ActionMailer::Base.delivery_method = original
  end

  before do
    allow_any_instance_of(ConversationReplyMailer).to receive(:set_delivery_method) # rubocop:disable RSpec/AnyInstance
    ActionMailer::Base.deliveries.clear
    ScanSolo::AiAgentConfig.draft_for!(account).update!(name: 'Agente', enabled: true, allowed_inbox_ids: [customer_inbox.id],
                                                        quote_inbox_id: email_inbox.id)
    ScanSolo::AiAgent::PublishService.new(account: account).call
    allow(ScanSolo::Quote::EmailThread).to receive(:post!).and_wrap_original do |original, **kwargs|
      transaction_open_at << ActiveRecord::Base.connection.current_transaction.joinable?
      original.call(**kwargs)
    end
  end

  def create_version(status: :awaiting_approval)
    proposal.versions.create!(status: status, quote_request: quote_request, value: 12_500, currency: 'BRL', artifact_url: artifact_url,
                              generate_callback_applied_at: Time.current).tap do |created|
      created.document.attach(io: StringIO.new('%PDF-1.4 proposta'), filename: "#{created.proposal_number}.pdf", content_type: 'application/pdf')
    end
  end

  def approve_and_deliver(target = version)
    ScanSolo::Proposal::ApproveService.call(proposal_version: target, actor: create(:user, account: account))
    perform_enqueued_jobs(only: ScanSolo::ProposalDeliveryJob)
    target.reload
  end

  def delivery_failures
    ScanSolo::AuditEvent.where(event_type: 'proposal.delivery_failed', subject: opportunity)
  end

  it 'posts one e-mail to the lead with the commercial recipient in CC and the stored PDF after approval (RF-11, CT-06)' do
    approve_and_deliver

    message = email_messages.sole
    expect(version).to have_attributes(status: 'approved', sent_message_id: message.id)
    expect(message.content_attributes).to include('to_emails' => ['ana@solar.example'], 'cc_emails' => ['comercial@scansolo.com.br'])
    expect(message.additional_attributes).to include('scansolo_origin' => 'proposal_email', 'scansolo_proposal_version_id' => version.id)
    expect(message.attachments.sole.file.blob.checksum).to eq(version.document.blob.checksum)
    expect(message.content).to include(version.proposal_number)
  end

  it 'opens the proposal thread on the lead contact, separate from the quote thread (RF-17, CT-06)' do
    approve_and_deliver

    thread = proposal.reload.email_conversation
    expect(thread).to eq(email_messages.sole.conversation)
    expect(thread).to have_attributes(inbox: email_inbox, contact: contact)
    expect(thread.additional_attributes).to include('scansolo_thread' => 'proposal_delivery')
  end

  it 'delivers the native e-mail with Cc comercial@scansolo.com.br and the PDF (RF-11)' do
    perform_enqueued_jobs(only: [ScanSolo::ProposalDeliveryJob, SendReplyJob]) do
      ScanSolo::Proposal::ApproveService.call(proposal_version: version, actor: create(:user, account: account))
    end

    expect(version.reload.sent_message.reload.source_id).to be_present
    mail = ActionMailer::Base.deliveries.sole
    expect(mail.to).to eq(['ana@solar.example'])
    expect(mail.cc).to eq(['comercial@scansolo.com.br'])
    expect(mail.attachments.sole).to have_attributes(filename: "#{version.proposal_number}.pdf", mime_type: 'application/pdf')
  end

  it 'sends nothing over WhatsApp and creates no Make request (RF-11)' do
    approve_and_deliver

    expect(conversation.messages.count).to eq(0)
    expect(ScanSolo::MakeRequest.count).to eq(0)
    expect(opportunity.reload).to be_qualificado
  end

  it 'sends one e-mail for two runs, sequential or concurrent (RF-12, RNF-02)' do
    approve_and_deliver

    described_class.call(proposal_version: version.reload)
    Array.new(2) { Thread.new { ScanSolo::ProposalDeliveryJob.perform_now(version.id) } }.each(&:join)

    expect(email_messages.count).to eq(1)
  end

  it 'reuses the proposal thread for version 2 after version 1 was rejected (RF-11, CT-06)' do
    approve_and_deliver
    version.update!(status: :rejected)
    second = create_version

    approve_and_deliver(second)

    expect(email_messages.count).to eq(2)
    expect(email_messages.pluck(:conversation_id).uniq).to eq([proposal.reload.email_conversation_id])
    expect(Conversation.where("additional_attributes ->> 'scansolo_thread' = 'proposal_delivery'").count).to eq(1)
    expect(second.sent_message.additional_attributes['scansolo_proposal_version_id']).to eq(second.id)
  end

  it 'fails with lead_email_missing when the contact has no e-mail, keeping the stage (RF-08, RF-14)' do
    ScanSolo::Proposal::ApproveService.call(proposal_version: version, actor: create(:user, account: account))
    contact.update!(email: nil)
    perform_enqueued_jobs(only: ScanSolo::ProposalDeliveryJob)

    expect(version.reload).to have_attributes(status: 'failed', failure_reason: 'lead_email_missing', value: 12_500, artifact_url: artifact_url)
    expect(version.document).to be_attached
    expect(delivery_failures.sole.payload).to include('reason' => 'lead_email_missing')
    expect(delivery_failures.sole.correlation_id).to eq(quote_request.correlation_id)
    expect(email_messages.count).to eq(0)
    expect(opportunity.reload).to be_qualificado
  end

  it 'fails with lead_email_missing on a malformed contact e-mail (RF-08)' do
    contact.update_column(:email, 'x@') # rubocop:disable Rails/SkipsModelValidations

    approve_and_deliver

    expect(version).to have_attributes(status: 'failed', failure_reason: 'lead_email_missing')
    expect(email_messages.count).to eq(0)
  end

  it 'fails with email_delivery_failed when no PDF is stored (RF-14)' do
    version.document.purge

    approve_and_deliver

    expect(version).to have_attributes(status: 'failed', failure_reason: 'email_delivery_failed')
    expect(delivery_failures.count).to eq(1)
    expect(email_messages.count).to eq(0)
  end

  it 'fails with email_delivery_failed when the message creation raises, keeping the stage (RF-14)' do
    allow(ScanSolo::Quote::EmailThread).to receive(:post!).and_raise(ActiveRecord::RecordInvalid)

    approve_and_deliver

    expect(version).to have_attributes(status: 'failed', failure_reason: 'email_delivery_failed', value: 12_500)
    expect(delivery_failures.count).to eq(1)
    expect(opportunity.reload).to be_qualificado
    expect(opportunity.cadence_enrollments).to be_none
  end

  it 'creates the e-mail outside any open transaction and refuses to run inside one (RNF-01)' do
    approve_and_deliver

    expect(transaction_open_at).to eq([false])
    expect { ActiveRecord::Base.transaction { described_class.call(proposal_version: version) } }
      .to raise_error(CustomExceptions::ScanSolo::DeliveryInsideTransaction)
  end

  it 'does not deliver a version that was never approved (RF-04)' do
    described_class.call(proposal_version: version)

    expect(version.reload).to be_awaiting_approval
    expect(email_messages.count).to eq(0)
  end

  describe 'explicit redelivery (RF-15 a)' do
    it 'resends the e-mail with the same PDF on the same thread for a failed approved version' do
      approve_and_deliver
      version.update!(status: :failed, failure_reason: 'email_delivery_failed')

      described_class.call(proposal_version: version, redeliver: true)

      expect(version.reload).to have_attributes(status: 'approved', failure_reason: nil, sent_message_id: email_messages.last.id)
      expect(email_messages.count).to eq(2)
      expect(email_messages.pluck(:conversation_id).uniq.size).to eq(1)
      expect(email_messages.last.attachments.sole.file.blob.checksum).to eq(version.document.blob.checksum)
    end

    it 'ignores a failed version that was never approved' do
      version.update!(status: :failed, failure_reason: 'artifact_download_failed')

      described_class.call(proposal_version: version, redeliver: true)

      expect(version.reload).to have_attributes(status: 'failed', failure_reason: 'artifact_download_failed')
      expect(email_messages.count).to eq(0)
    end
  end
end
