require 'rails_helper'

RSpec.describe ScanSolo::Proposal::MakeProvider do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:config_v2_labels) do
    ['Objetivo do serviço', 'Cidade / UF', 'Endereço da obra', 'Área ou extensão', 'Profundidade de interesse',
     'Prazo desejado', 'Integração de segurança', 'Empresa', 'E-mail']
  end
  let(:contact) do
    create(:contact, account: account, name: 'Leonardo', email: 'leo@example.com',
                     custom_attributes: { 'Cidade / UF' => 'Rio/RJ', 'Área ou extensão' => '800 m²', 'Empresa' => '',
                                          'Integração de segurança' => 'NR-35', 'budget' => '5000' })
  end
  let(:expected_qualification) { { 'cidade_uf' => 'Rio/RJ', 'area' => '800 m²', 'email' => 'leo@example.com', 'nome' => 'Leonardo' } }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :qualificado)
  end
  let(:proposal) { ScanSolo::Proposal.create!(opportunity: opportunity) }
  let(:correlation_id) { SecureRandom.uuid }
  let(:quote_request) do
    ScanSolo::QuoteRequest.create!(
      account: account, opportunity: opportunity, correlation_id: SecureRandom.uuid, status: :replied, replied_at: Time.current,
      commercial: { 'total_value' => '12500.0', 'schedule' => '30 dias', 'scope' => "Sondagem SPT\n3 furos", 'payment_terms' => '50% na assinatura',
                    'notes' => nil }
    )
  end
  let(:expected_commercial) do
    { total_value: 12_500.0, total_value_in_words: 'doze mil e quinhentos reais', currency: 'BRL', schedule: '30 dias',
      scope: "Sondagem SPT\n3 furos", payment_terms: '50% na assinatura', quote_request_id: quote_request.id }
  end
  let(:version) { proposal.versions.create!(generate_correlation_id: correlation_id, quote_request: quote_request) }

  before do
    ScanSolo::AiAgentConfig.draft_for!(account).update!(required_qualification_fields: config_v2_labels)
    ScanSolo::AiAgent::PublishService.new(account: account).call
  end

  # CT-05 (RNF-11): the payload gains `proposal_number` and `commercial`; every current key is unchanged.
  it 'delegates generation to the existing transport with correlation, qualification and commercial data' do
    freeze_time do
      expect(ScanSolo::Make::OutboundRequestService).to receive(:call).with(
        account: account, action: 'proposal.generate', correlation_id: correlation_id, idempotency_key: correlation_id, retry_count: 0,
        payload: {
          account_id: account.id, opportunity_id: opportunity.id, proposal_version_id: version.id, proposal_number: version.proposal_number,
          qualification: expected_qualification, requested_by_user_id: user.id, requested_at: Time.current.iso8601,
          commercial: expected_commercial
        }
      )

      described_class.request_generation(proposal_version: version, correlation_id: correlation_id, actor: user)
    end
  end

  it 'sends a null requested_by_user_id for AI-initiated requests' do
    expect(ScanSolo::Make::OutboundRequestService).to receive(:call)
      .with(hash_including(payload: hash_including(requested_by_user_id: nil)))

    described_class.request_generation(proposal_version: version, correlation_id: correlation_id)
  end

  it 'delegates sends without inventing a commercial value or artifact' do
    expect(ScanSolo::Make::OutboundRequestService).to receive(:call).with(
      hash_including(action: 'proposal.send', correlation_id: correlation_id, idempotency_key: correlation_id)
    )

    described_class.request_send(proposal_version: version, correlation_id: correlation_id, conversation: conversation)
    expect(version.reload.value).to be_nil
    expect(version.artifact_url).to be_nil
  end

  describe 'RF-37: HTTP transport through WebMock' do
    let(:scenario_url) { 'https://hook.make.example/scenario-webhook' }

    before do
      allow(Rails.application.credentials).to receive(:dig).and_call_original
      allow(Rails.application.credentials).to receive(:dig).with(:scan_solo, :make, :scenario_url).and_return(scenario_url)
      allow(Rails.application.credentials).to receive(:dig).with(:scan_solo, :make, :secret).and_return('make-outbound-secret')
    end

    it 'persists a MakeRequest carrying the version correlation id and posts the CT-05 payload' do
      stub_request(:post, scenario_url).to_return(status: 200, body: '{}')

      request = described_class.request_generation(proposal_version: version, correlation_id: correlation_id, actor: user)

      expect(request).to be_sent
      expect(request.correlation_id).to eq(version.generate_correlation_id)
      expect(
        a_request(:post, scenario_url).with do |req|
          body = JSON.parse(req.body)
          body['action'] == 'proposal.generate' && body['proposal_version_id'] == version.id &&
            body['qualification'] == expected_qualification && body['requested_by_user_id'] == user.id && body['requested_at'].present?
        end
      ).to have_been_made.once
      expect(version.reload).to be_generating
    end

    # CT-05 (RNF-11): validated against the operação centralizada contract, which requires `proposal_number` and `commercial`.
    it 'posts a payload valid against the CT-05 MakeIntegrationRequestPayload schema' do
      stub_request(:post, scenario_url).to_return(status: 200, body: '{}')
      asyncapi = YAML.safe_load_file(Rails.root.join('.spec/features/scansolo-operacao-centralizada/asyncapi.yaml'))
      schema = JSONSchemer.schema(
        asyncapi.dig('components', 'schemas', 'MakeIntegrationRequestPayload').merge('components' => asyncapi['components'])
      )

      described_class.request_generation(proposal_version: version, correlation_id: correlation_id, actor: user)

      expect(a_request(:post, scenario_url).with { |req| schema.valid?(JSON.parse(req.body)) }).to have_been_made.once
    end

    {
      'timeout' => ->(stub) { stub.to_timeout },
      'network_error' => ->(stub) { stub.to_raise(SocketError) },
      'provider_unavailable' => ->(stub) { stub.to_return(status: 503, body: 'down') }
    }.each do |reason, configure|
      it "marks the version failed with #{reason} without raising" do
        configure.call(stub_request(:post, scenario_url))

        expect do
          described_class.request_generation(proposal_version: version, correlation_id: correlation_id)
        end.not_to raise_error

        expect(version.reload).to be_failed
        expect(version.failure_reason).to eq(reason)
        expect(ScanSolo::MakeRequest.find_by(correlation_id: correlation_id)).to be_failed
      end
    end
  end

  describe 'CT-05 commercial data (RF-24, RF-26, RF-47)' do
    let(:payloads) { [] }

    before do
      allow(ScanSolo::Make::OutboundRequestService).to receive(:call) { |**kwargs| payloads << kwargs }
    end

    it 'sends the proposal number, the commercial reply and the amount in words without any LLM call' do
      allow(ScanSolo::AiTurn::ModelInvoker).to receive(:call).and_raise('LLM must not be called (RF-47)')
      allow(RubyLLM).to receive(:context).and_raise('LLM must not be called (RF-47)')

      described_class.request_generation(proposal_version: version, correlation_id: correlation_id)

      request = payloads.sole
      expect(request).to include(idempotency_key: correlation_id, correlation_id: correlation_id)
      expect(request[:payload]).to include(proposal_number: version.proposal_number, commercial: expected_commercial)
      expect(version.proposal_number).to match(/\ASS-\d{4}-\d{6}\z/)
      expect(ScanSolo::AiTurn::ModelInvoker).not_to have_received(:call)
      expect(RubyLLM).not_to have_received(:context)
    end

    it 'sends the commercial notes only when present' do
      quote_request.update!(commercial: quote_request.commercial.merge('notes' => 'Mobilização inclusa'))

      described_class.request_generation(proposal_version: version, correlation_id: correlation_id)

      expect(payloads.sole[:payload][:commercial]).to include(notes: 'Mobilização inclusa')
    end

    it 'sends qualification.projeto with the cliente_final value' do
      ScanSolo::LeadState::Writer.new(lead_state: opportunity.lead_state)
                                 .apply_field!(key: 'cliente_final', value: 'Hospital Central', status: 'confirmado', source_message_id: nil)

      described_class.request_generation(proposal_version: version, correlation_id: correlation_id)

      expect(payloads.sole[:payload][:qualification]).to eq(expected_qualification.merge('projeto' => 'Hospital Central'))
    end
  end

  describe 'CT-05 canonical qualification (RF-15)' do
    let(:payloads) { [] }

    before do
      allow(ScanSolo::Make::OutboundRequestService).to receive(:call) { |**kwargs| payloads << kwargs[:payload] }
    end

    def qualification
      described_class.request_generation(proposal_version: version, correlation_id: correlation_id)
      payloads.last[:qualification]
    end

    it 'sends only canonical keys with the stored values, whatever the config label spelling' do
      expect(qualification).to eq(expected_qualification)
      expect(qualification.keys).to all(match(/\A[a-z0-9_]+\z/))
      expect(qualification.keys - ScanSolo::Qualification::FieldResolver::MAKE_KEYS).to be_empty
    end

    it 'sends native nome and telefone even when the config does not require them' do
      contact.update!(phone_number: '+5521999990000')

      expect(qualification).to include('nome' => 'Leonardo', 'telefone' => '+5521999990000')
    end

    it 'omits keys without a present value and never sends integracao_seguranca' do
      expect(qualification).not_to have_key('empresa')
      expect(qualification).not_to have_key('integracao_seguranca')
      expect(qualification.values).to all(be_present)
    end

    it 'prefers the lead state value over the Contact and keeps the key set present-only (lead state RF-08)' do
      writer = ScanSolo::LeadState::Writer.new(lead_state: opportunity.lead_state)
      writer.apply_field!(key: 'area', value: '1.200 m²', status: 'confirmado', source_message_id: nil)
      writer.apply_field!(key: 'profundidade', value: '3 m', status: 'confirmado', source_message_id: nil)

      expect(qualification).to eq(expected_qualification.merge('area' => '1.200 m²', 'profundidade' => '3 m'))
      expect(qualification.keys - ScanSolo::Qualification::FieldResolver::MAKE_KEYS).to be_empty
    end
  end
end
