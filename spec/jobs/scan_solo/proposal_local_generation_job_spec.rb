# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::ProposalLocalGenerationJob do
  let(:convert_url) { 'http://gotenberg.test:3000/forms/libreoffice/convert' }
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :qualificado)
  end
  let(:quote_request) do
    ScanSolo::QuoteRequest.create!(account: account, opportunity: opportunity, correlation_id: SecureRandom.uuid, status: :replied,
                                   replied_at: Time.current,
                                   commercial: { 'total_value' => '12500.00', 'schedule' => '30 dias', 'scope' => 'Sondagem',
                                                 'payment_terms' => 'À vista' })
  end
  let(:correlation_id) { SecureRandom.uuid }
  let(:version) do
    ScanSolo::Proposal.create!(opportunity: opportunity).versions.create!(generate_correlation_id: correlation_id, quote_request: quote_request)
  end
  let(:template_bytes) { scan_solo_docx_valid }
  let(:failed_events) { ScanSolo::AuditEvent.where(event_type: 'proposal.generation_failed') }

  around do |example|
    with_modified_env(SCANSOLO_GOTENBERG_URL: 'http://gotenberg.test:3000') { example.run }
  end

  before do
    ScanSolo::ProposalTemplate.new(account: account, filename: 'proposta.docx', byte_size: template_bytes.bytesize,
                                   sha256: Digest::SHA256.hexdigest(template_bytes), active: true).tap do |record|
      record.file.attach(io: StringIO.new(template_bytes), filename: 'proposta.docx')
      record.save!
    end
  end

  it 'runs on the medium queue (CT-02)' do
    expect(described_class.new.queue_name).to eq('medium')
  end

  it 'retries a 5xx 30 s and 2 min later and fails with provider_unavailable after 3 attempts (RF-11)' do
    stub_request(:post, convert_url).to_return(status: 503)
    freeze_time

    described_class.perform_now(version.id, correlation_id)
    expect(described_class).to have_been_enqueued.with(version.id, correlation_id).at(30.seconds.from_now)
    perform_enqueued_jobs(only: described_class)
    expect(described_class).to have_been_enqueued.with(version.id, correlation_id).at(2.minutes.from_now)
    expect(version.reload).to be_generating
    perform_enqueued_jobs(only: described_class)

    expect(a_request(:post, convert_url)).to have_been_made.times(3)
    expect(version.reload).to have_attributes(status: 'failed', failure_reason: 'provider_unavailable')
    expect(failed_events.sole.payload).to include('reason' => 'provider_unavailable', 'cause' => 'conversion')
    expect(enqueued_jobs.select { |job| job['job_class'] == described_class.name }).to be_empty
  end

  it 'generates the proposal when a 5xx is followed by a 200' do
    stub_request(:post, convert_url).to_return({ status: 503 }, { status: 200, body: Rails.root.join('spec/assets/sample.pdf').binread })

    perform_enqueued_jobs(only: described_class) { described_class.perform_later(version.id, correlation_id) }

    expect(a_request(:post, convert_url)).to have_been_made.twice
    expect(version.reload).to be_awaiting_approval
    expect(version.document).to be_attached
    expect(failed_events).to be_empty
  end

  it 'does not retry a 4xx (RF-11)' do
    stub_request(:post, convert_url).to_return(status: 400)

    perform_enqueued_jobs(only: described_class) { described_class.perform_later(version.id, correlation_id) }

    expect(a_request(:post, convert_url)).to have_been_made.once
    expect(version.reload).to have_attributes(status: 'failed', failure_reason: 'provider_rejected')
  end
end
