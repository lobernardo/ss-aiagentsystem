# frozen_string_literal: true

require 'rails_helper'

# RF-21 / CT-04 replace the OC/RF-73..RF-80 `proposal.send` expectations: the legacy send never reaches Make; it only hands
# an approved version to the idempotent e-mail delivery (RF-11, RF-12).
RSpec.describe ScanSolo::Proposal::SendService do
  let(:account) { create(:account) }
  let(:customer_inbox) { create(:inbox, account: account) }
  let(:email_inbox) { create(:channel_email, account: account, email: 'atendimento.comercial@scansolo.com.br').inbox }
  let(:contact) { create(:contact, account: account, email: 'ana@solar.example') }
  let(:conversation) { create(:conversation, account: account, inbox: customer_inbox, contact: contact) }
  let(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :qualificado)
  end
  let(:proposal) { ScanSolo::Proposal.create!(opportunity: opportunity) }
  let(:agent) { create(:user, account: account) }
  let(:proposal_emails) { Message.where(inbox: email_inbox).outgoing }

  before do
    ScanSolo::AiAgentConfig.draft_for!(account).update!(name: 'Agente', enabled: true, allowed_inbox_ids: [customer_inbox.id],
                                                        quote_inbox_id: email_inbox.id)
    ScanSolo::AiAgent::PublishService.new(account: account).call
  end

  def create_version(status)
    proposal.versions.create!(status: status, value: 1000, currency: 'BRL', artifact_url: 'https://x.test/a.pdf',
                              generate_callback_applied_at: Time.current, approved_at: Time.current, approved_by: agent).tap do |created|
      created.document.attach(io: StringIO.new('%PDF-1.4 proposta'), filename: "#{created.proposal_number}.pdf", content_type: 'application/pdf')
    end
  end

  def call(version)
    described_class.call(proposal_version: version, correlation_id: SecureRandom.uuid, conversation: conversation, actor: agent)
  end

  def expect_rejection(version, code)
    expect { call(version) }.to raise_error(CustomExceptions::ScanSolo::ProposalActionRejected, code)
  end

  it 'rejects a sent version with already_sent and creates no Make request' do
    version = create_version(:sent)

    expect { expect_rejection(version, 'already_sent') }.not_to change(ScanSolo::MakeRequest, :count)
    expect(proposal_emails.count).to eq(0)
  end

  it 'rejects a version awaiting approval with approval_required' do
    version = create_version(:awaiting_approval)

    expect_rejection(version, 'approval_required')
    expect(version.reload).to be_awaiting_approval
    expect(proposal_emails.count).to eq(0)
  end

  it 'rejects a non-current version with not_current_version' do
    stale = create_version(:approved)
    stale.update!(status: :rejected)
    create_version(:approved)

    expect_rejection(stale.reload, 'not_current_version')
  end

  it 'delivers an approved version by e-mail once, without proposal.send (RF-11)' do
    version = create_version(:approved)

    expect { call(version) }.to change(proposal_emails, :count).by(1).and not_change(ScanSolo::MakeRequest, :count)

    expect(version.reload).to have_attributes(status: 'approved', sent_message: proposal_emails.sole, send_correlation_id: nil)
  end

  it 'sends 0 new e-mails for an approved version already delivered (RF-12)' do
    version = create_version(:approved)
    ScanSolo::Proposal::DeliveryService.call(proposal_version: version)

    expect { call(version.reload) }.not_to change(proposal_emails, :count)
    expect(ScanSolo::MakeRequest.count).to eq(0)
  end
end
