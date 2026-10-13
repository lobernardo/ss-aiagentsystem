# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Proposal::LocalGenerationService do
  subject(:generate) { described_class.call(proposal_version_id: version.id, correlation_id: correlation_id) }

  let(:convert_url) { 'http://gotenberg.test:3000/forms/libreoffice/convert' }
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, name: '', email: nil, phone_number: nil, custom_attributes: {}) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :qualificado)
  end
  let(:quote_request) do
    ScanSolo::QuoteRequest.create!(account: account, opportunity: opportunity, correlation_id: SecureRandom.uuid, status: :replied,
                                   replied_at: Time.current,
                                   commercial: { 'total_value' => '12500.00', 'schedule' => '30 dias', 'scope' => 'Sondagem sintética',
                                                 'payment_terms' => '50% na assinatura' })
  end
  let(:correlation_id) { SecureRandom.uuid }
  let!(:version) do
    ScanSolo::Proposal.create!(opportunity: opportunity).versions.create!(generate_correlation_id: correlation_id, quote_request: quote_request)
  end
  let(:template_bytes) { scan_solo_docx_valid }
  let(:template_account) { account }
  let!(:template) do
    ScanSolo::ProposalTemplate.new(account: template_account, filename: 'proposta.docx', byte_size: template_bytes.bytesize,
                                   sha256: Digest::SHA256.hexdigest(template_bytes), active: true).tap do |record|
      record.file.attach(io: StringIO.new(template_bytes), filename: 'proposta.docx',
                         content_type: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document')
      record.save!
    end
  end
  let(:generated_events) { ScanSolo::AuditEvent.where(event_type: 'proposal.generated') }
  let(:failed_events) { ScanSolo::AuditEvent.where(event_type: 'proposal.generation_failed') }
  let(:pdf_blobs) { ActiveStorage::Blob.where(content_type: 'application/pdf') }

  around do |example|
    with_modified_env(SCANSOLO_GOTENBERG_URL: 'http://gotenberg.test:3000') { example.run }
  end

  before { stub_request(:post, convert_url).to_return(status: 200, body: file_fixture('sample.pdf').binread) }

  def expect_failed(reason, cause, placeholders: nil)
    version.reload
    expect(version).to have_attributes(status: 'failed', failure_reason: reason, value: nil, artifact_sha256: nil)
    expect(version.document).not_to be_attached
    expect(failed_events.sole.payload).to eq(
      { 'proposal_version_id' => version.id, 'reason' => reason, 'generate_correlation_id' => correlation_id, 'cause' => cause,
        'placeholders' => placeholders }.compact
    )
    expect(generated_events).to be_empty
  end

  describe 'success (RF-10)' do
    it 'attaches the PDF and applies the result through the CallbackHandler' do
      generate

      version.reload
      expect(version).to have_attributes(status: 'awaiting_approval', value: BigDecimal('12500.00'), currency: 'BRL', artifact_url: nil,
                                         failure_reason: nil)
      expect(version.document.filename.to_s).to eq("#{version.proposal_number}.pdf")
      expect(version.document.content_type).to eq('application/pdf')
      expect(version.artifact_sha256).to eq(Digest::SHA256.hexdigest(version.document.download))
      expect(version.valid_until.to_date).to eq(Time.use_zone('America/Sao_Paulo') { Time.zone.today } + 90)
    end

    it 'audits proposal.generated with the template version after 1 conversion request' do
      generate

      expect(generated_events.sole.payload['template_version']).to match(/\A\d+:\h{64}\z/)
      expect(generated_events.sole.payload['template_version']).to eq(template.template_version)
      expect(failed_events).to be_empty
      expect(a_request(:post, convert_url)
               .with { |request| request.body.include?("filename=\"#{version.proposal_number}.docx\"") }).to have_been_made.once
    end

    it 'never converts nor attaches twice when run again (RF-03, RF-14)' do
      2.times { described_class.call(proposal_version_id: version.id, correlation_id: correlation_id) }

      expect(a_request(:post, convert_url)).to have_been_made.once
      expect(ActiveStorage::Attachment.where(record: version, name: 'document').count).to eq(1)
      expect(pdf_blobs.count).to eq(1)
      expect(generated_events.count).to eq(1)
    end

    context 'with every qualification field faltante or nao_informado (RF-24)' do
      before do
        opportunity.lead_state.update!(fields: {
                                         'nome' => { 'status' => 'faltante' }, 'empresa' => { 'status' => 'nao_informado', 'value' => 'não sei' },
                                         'cidade_uf' => { 'status' => 'faltante' }, 'profundidade' => { 'status' => 'nao_informado' }
                                       })
      end

      it 'still generates the proposal' do
        generate

        expect(version.reload).to be_awaiting_approval
        expect(failed_events).to be_empty
      end
    end
  end

  describe 'RF-03: a run that is no longer the open generation has no effect' do
    it 'ignores an old correlation id' do
      expect do
        described_class.call(proposal_version_id: version.id, correlation_id: SecureRandom.uuid)
      end.not_to(change { [version.reload.attributes, ScanSolo::AuditEvent.count, ActiveStorage::Blob.count] })
      expect(a_request(:post, convert_url)).not_to have_been_made
    end

    it 'ignores a missing version' do
      expect { described_class.call(proposal_version_id: 0, correlation_id: correlation_id) }.not_to change(ScanSolo::AuditEvent, :count)
      expect(a_request(:post, convert_url)).not_to have_been_made
    end

    %w[awaiting_approval failed rejected].each do |status|
      it "ignores a #{status} version" do
        version.update!(status: status)

        expect { generate }.not_to(change { [version.reload.attributes, ScanSolo::AuditEvent.count, ActiveStorage::Blob.count] })
        expect(a_request(:post, convert_url)).not_to have_been_made
      end
    end
  end

  describe 'template failures (RF-04, RF-07, RF-08, RF-21)' do
    context 'without an active template' do
      let(:template_account) { create(:account) }

      it 'fails with template_unavailable even when another account has one, without any HTTP' do
        generate

        expect_failed('template_unavailable', 'template')
        expect(a_request(:post, convert_url)).not_to have_been_made
      end
    end

    context 'without a quote request (legacy version)' do
      let(:version) do
        ScanSolo::Proposal.create!(opportunity: opportunity).versions.create!(generate_correlation_id: correlation_id)
      end

      it 'fails with template_render_failed, without any HTTP' do
        generate

        expect_failed('template_render_failed', 'template')
        expect(a_request(:post, convert_url)).not_to have_been_made
      end
    end

    context 'with a residual placeholder in the stored template' do
      let(:template_bytes) { scan_solo_docx(paragraphs: ['Proposta {{NUMERO_PROPOSTA}} {{XYZ}}']) }

      it 'fails with template_render_failed and the placeholder names, without any HTTP' do
        generate

        expect_failed('template_render_failed', 'template', placeholders: ['XYZ'])
        expect(a_request(:post, convert_url)).not_to have_been_made
      end
    end
  end

  describe 'conversion failures (RF-09, RF-11)' do
    it 'fails a 200 that is not a PDF with cause conversion, leaving no blob' do
      stub_request(:post, convert_url).to_return(status: 200, body: '<html>erro</html>')

      expect { generate }.not_to change(ActiveStorage::Blob, :count)
      expect_failed('template_render_failed', 'conversion')
    end

    it 'fails a 4xx with provider_rejected after 1 request' do
      stub_request(:post, convert_url).to_return(status: 400)

      generate

      expect_failed('provider_rejected', 'conversion')
      expect(a_request(:post, convert_url)).to have_been_made.once
    end

    it 'propagates a 5xx to the job retry, leaving the version generating' do
      stub_request(:post, convert_url).to_return(status: 503)

      expect { generate }.to(raise_error { |error| expect(error.class.name).to eq('CustomExceptions::ScanSolo::GotenbergUnavailable') })
      expect(version.reload).to be_generating
      expect(failed_events).to be_empty
    end
  end

  describe 'unexpected exceptions (RF-12)' do
    before { allow(ChatwootExceptionTracker).to receive(:new).and_call_original }

    it 'fails a blob upload error with cause exception and reports it once' do
      allow(ActiveStorage::Blob).to receive(:create_and_upload!).and_raise(StandardError, 'storage down')

      generate

      expect_failed('template_render_failed', 'exception')
      expect(ChatwootExceptionTracker).to have_received(:new).once
      expect(pdf_blobs).to be_empty
    end

    it 'fails an attach error with cause exception and purges the uploaded blob' do
      allow_any_instance_of(ActiveStorage::Attached::One).to receive(:attach).and_raise(StandardError, 'attach failed') # rubocop:disable RSpec/AnyInstance

      generate

      expect_failed('template_render_failed', 'exception')
      expect(ChatwootExceptionTracker).to have_received(:new).once
      expect(pdf_blobs).to be_empty
    end
  end

  describe 'concurrent loser between upload and lock (RF-10)' do
    it 'attaches nothing and purges its blob when another run applied the result' do
      allow(ActiveStorage::Blob).to receive(:create_and_upload!).and_wrap_original do |original, **args|
        original.call(**args).tap do
          ScanSolo::Proposal::CallbackHandler.apply_generate_result!(proposal_version: ScanSolo::ProposalVersion.find(version.id),
                                                                     correlation_id: correlation_id, success: true, value: 1, currency: 'BRL')
        end
      end

      generate

      expect(version.reload.document).not_to be_attached
      expect(version.value).to eq(1)
      expect(pdf_blobs).to be_empty
    end

    it 'attaches nothing and purges its blob when the version failed (Reprocessar) in between' do
      allow(ActiveStorage::Blob).to receive(:create_and_upload!).and_wrap_original do |original, **args|
        original.call(**args).tap { ScanSolo::ProposalVersion.find(version.id).update!(status: :failed, failure_reason: 'provider_rejected') }
      end

      generate

      expect(version.reload).to have_attributes(status: 'failed', value: nil)
      expect(version.document).not_to be_attached
      expect(pdf_blobs).to be_empty
      expect(generated_events).to be_empty
    end
  end

  describe '.exhausted!' do
    it 'fails the version with provider_unavailable and cause conversion (RF-11)' do
      described_class.exhausted!(proposal_version_id: version.id, correlation_id: correlation_id)

      expect_failed('provider_unavailable', 'conversion')
    end
  end
end
