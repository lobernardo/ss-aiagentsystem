# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Proposal::LocalProvider do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :qualificado)
  end
  let(:quote_request) do
    ScanSolo::QuoteRequest.create!(account: account, opportunity: opportunity, correlation_id: SecureRandom.uuid, status: :replied,
                                   replied_at: Time.current,
                                   commercial: { 'total_value' => '12500.0', 'schedule' => '30 dias', 'scope' => 'Sondagem SPT',
                                                 'payment_terms' => '50% na assinatura' })
  end
  let(:correlation_id) { SecureRandom.uuid }

  around do |example|
    with_modified_env(SCANSOLO_GOTENBERG_URL: 'http://gotenberg.test:3000') { example.run }
  end

  before do
    ScanSolo::AiAgentConfig.draft_for!(account).update!(name: 'Agente', enabled: true, required_qualification_fields: ['Área'])
    ScanSolo::AiAgent::PublishService.new(account: account).call
    ScanSolo::LeadState::Writer.new(lead_state: opportunity.lead_state)
                               .apply_field!(key: 'area', value: '800 m²', status: 'confirmado', source_message_id: nil)
  end

  it 'only enqueues the local generation job on the medium queue through the GenerateService (RF-02, CT-01)' do
    version = nil
    expect do
      version = ScanSolo::Proposal::GenerateService.call(opportunity: opportunity, quote_request: quote_request, correlation_id: correlation_id)
    end.to have_enqueued_job(ScanSolo::ProposalLocalGenerationJob).once

    expect(version).to be_generating
    expect(version.document).not_to be_attached
    expect(ScanSolo::ProposalLocalGenerationJob).to have_been_enqueued.once.on_queue('medium').with(version.id, correlation_id)
    expect(a_request(:any, /.*/)).not_to have_been_made
  end

  it 'enqueues nothing when the surrounding transaction rolls back' do
    version = ScanSolo::Proposal.create!(opportunity: opportunity).versions.create!(generate_correlation_id: correlation_id,
                                                                                    quote_request: quote_request)

    ActiveRecord::Base.transaction do
      described_class.request_generation(proposal_version: version, correlation_id: correlation_id, actor: nil)
      raise ActiveRecord::Rollback
    end

    expect(ScanSolo::ProposalLocalGenerationJob).not_to have_been_enqueued
  end
end
