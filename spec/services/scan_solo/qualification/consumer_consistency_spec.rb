# frozen_string_literal: true

require 'rails_helper'

# Lead state RF-08 / RNF-08: the six consumers of the "qualification field
# satisfied?" rule all delegate to ScanSolo::Qualification::FieldResolver, so
# for the same opportunity and published config they agree on which labels
# are satisfied (confirmado in the lead state) and which are missing, and
# both sets equal the lead_state status block (Projection#status). Data only
# in the Contact (native columns or custom attributes) is seeded `inferido`
# and stays missing in every consumer.
RSpec.describe 'ScanSolo qualification consumer consistency' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:labels) do
    ['Nome', 'Objetivo do serviço', 'Cidade / UF', 'Endereço da obra', 'Área ou extensão', 'Profundidade de interesse',
     'Prazo desejado', 'Integração de segurança', 'Empresa', 'E-mail']
  end
  let(:contact) do
    create(:contact, account: account, name: 'Leonardo', email: 'leo@example.com',
                     custom_attributes: { 'razão social' => 'ACME', 'profundidade' => '3 m', 'objective' => 'obra nova' })
  end
  let(:confirmed) do
    { 'tipo_intervencao' => 'Sondagem', 'cidade_uf' => 'Rio/RJ', 'endereco_obra' => 'Rua A 10', 'area' => '800 m²', 'prazo_desejado' => 'amanhã' }
  end
  let(:expected_missing) { ['Nome', 'Profundidade de interesse', 'Integração de segurança', 'Empresa', 'E-mail'] }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let!(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :em_qualificacao)
  end
  let(:message) do
    create(:message, account: account, conversation: conversation, message_type: :incoming, sender: contact, content: 'Olá')
  end

  let(:status) do
    ScanSolo::LeadState::Projection.call(opportunity: opportunity.reload, config: ScanSolo::AiAgentConfig.published_for(account)).status
  end
  let(:pipeline_context) do
    retrieval = ->(**) { { results: [], failure_reason: nil } }
    reading = ScanSolo::AiTurn::AttachmentReader::Result.new(updates: [], evidence: [], urls: [])
    ScanSolo::AiTurn::ContextAssembler.call(message: message, config: ScanSolo::AiAgentConfig.published_for(account), attachment_reading: reading,
                                            retrieval_service: retrieval)[:pipeline_context]
  end
  let(:reply_completeness_missing) { ScanSolo::Cadence::ReplyCompletenessDetector.call(opportunity: opportunity.reload).missing_fields }
  # RF-25 (RNF-11): generation needs the validated quote reply, so the field gate is what is compared.
  let(:generate_service_missing) do
    quote_request = ScanSolo::QuoteRequest.create!(account: account, opportunity: opportunity, correlation_id: SecureRandom.uuid, status: :replied)
    ScanSolo::Proposal::GenerateService.call(opportunity: opportunity.reload, quote_request: quote_request, correlation_id: SecureRandom.uuid,
                                             provider: ScanSolo::Proposal::MockProvider)
    []
  rescue ActiveRecord::RecordInvalid => e
    e.record.errors[:base].sole.delete_prefix('campos obrigatórios da proposta incompletos: ').split(', ')
  end
  let(:handoff_satisfied) do
    ScanSolo::Handoff::HandoffService.call(conversation: conversation, reason: 'transferência', actor: create(:user, account: account))
    line = conversation.messages.where(private: true).sole.content.lines(chomp: true)
                       .find { |candidate| candidate.start_with?('Campos de qualificação coletados: ') }
    entries = line.delete_prefix('Campos de qualificação coletados: ').split(', ')
    labels.select { |label| entries.any? { |entry| entry.start_with?("#{label}: ") } }
  end
  # Make only carries the fixed canonical key set and sends present values
  # (CT-05): every confirmed field (all of them Make keys here) must be in
  # the payload with its lead state value.
  let(:make_qualification) do
    payload = nil
    allow(ScanSolo::Make::OutboundRequestService).to receive(:call) { |**kwargs| payload = kwargs[:payload] }
    version = ScanSolo::Proposal.create!(opportunity: opportunity).versions.create!(generate_correlation_id: SecureRandom.uuid)
    ScanSolo::Proposal::MakeProvider.request_generation(proposal_version: version, correlation_id: version.generate_correlation_id)
    payload[:qualification]
  end

  def canonical_keys(field_labels)
    field_labels.map { |label| ScanSolo::Qualification::FieldResolver.canonical_key(label) }
  end

  before do
    draft = ScanSolo::AiAgentConfig.draft_for!(account)
    draft.update!(name: 'Agente', enabled: true, required_qualification_fields: labels, allowed_inbox_ids: [conversation.inbox_id])
    ScanSolo::AiAgent::PublishService.new(account: account).call
    writer = ScanSolo::LeadState::Writer.new(lead_state: opportunity.lead_state)
    confirmed.each { |key, value| writer.apply_field!(key: key, value: value, status: 'confirmado', source_message_id: nil) }
  end

  it 'derives identical satisfied and missing sets from every consumer, equal to lead_state.status', :aggregate_failures do
    missing_by_consumer = {
      context_assembler: pipeline_context[:missing_fields],
      context_assembler_collected: labels - pipeline_context[:collected_fields].keys,
      reply_completeness_detector: reply_completeness_missing,
      generate_service: generate_service_missing,
      handoff_service: labels - handoff_satisfied
    }

    missing_by_consumer.each do |consumer, missing|
      expect(missing).to match_array(expected_missing), "#{consumer} missing: #{missing.inspect}"
      expect(labels - missing).to match_array((labels - expected_missing)), "#{consumer} satisfied: #{(labels - missing).inspect}"
    end
    expect(status[:missing_fields]).to match_array(canonical_keys(expected_missing))
    expect(status[:confirmed_fields]).to match_array(canonical_keys((labels - expected_missing)))
    expect(make_qualification.slice(*confirmed.keys)).to eq(confirmed)
  end

  it 'keeps data present only in the Contact missing in every consumer' do
    contact_only = ['Nome', 'Profundidade de interesse', 'Empresa', 'E-mail']

    [pipeline_context[:missing_fields], reply_completeness_missing, generate_service_missing, labels - handoff_satisfied].each do |missing|
      expect(missing & contact_only).to match_array(contact_only)
    end
    expect(status[:missing_fields] & canonical_keys(contact_only)).to match_array(canonical_keys(contact_only))
    expect(status[:confirmed_fields] & canonical_keys(contact_only)).to be_empty
  end

  it 'gates the proposal only by faltante fields once the qualification is concluida, without changing satisfaction' do
    ScanSolo::LeadState::Writer.new(lead_state: opportunity.lead_state).complete!(at: Time.current)

    resolver = ScanSolo::Qualification::FieldResolver.call(opportunity: opportunity.reload, config: ScanSolo::AiAgentConfig.published_for(account))
    expect(resolver.proposal_gate_missing_labels).to eq(['Integração de segurança'])
    expect(resolver.missing_labels).to match_array(expected_missing)
    expect(status[:missing_fields]).to match_array(canonical_keys(expected_missing))
  end

  describe 'QualificationFieldAction' do
    fields = { 'nome' => 'Leonardo', 'profundidade' => '3 m', 'Integração de segurança' => 'NR-35', 'razão social' => 'ACME',
               'email' => 'leo@example.com' }.freeze

    it 'confirms exactly what the other consumers report missing, after which none of them reports a missing field' do
      turn = ScanSolo::AiTurn.create!(message: message, conversation: conversation, correlation_id: SecureRandom.uuid)
      result = ScanSolo::Actions::QualificationFieldAction.call(params: { conversation_id: conversation.id, fields: fields }, turn: turn)

      expect(result[:state_changes].pluck(:key)).to match_array(canonical_keys(expected_missing))
      expect([pipeline_context[:missing_fields], reply_completeness_missing, generate_service_missing, status[:missing_fields]]).to all(be_empty)
    end

    it 'leaves every consumer reporting the one field it did not confirm' do
      turn = ScanSolo::AiTurn.create!(message: message, conversation: conversation, correlation_id: SecureRandom.uuid)
      ScanSolo::Actions::QualificationFieldAction.call(params: { conversation_id: conversation.id, fields: fields.except('razão social') },
                                                       turn: turn)

      expect([pipeline_context[:missing_fields], reply_completeness_missing, generate_service_missing]).to all(eq(['Empresa']))
      expect(status[:missing_fields]).to eq(['empresa'])
    end
  end

  describe 'static single-reader check' do
    %w[
      ai_turn/context_assembler actions/qualification_field_action cadence/reply_completeness_detector
      proposal/generate_service proposal/make_provider handoff/handoff_service
    ].each do |consumer|
      it "keeps #{consumer} free of its own satisfaction rule" do
        source = Rails.root.join("app/services/scan_solo/#{consumer}.rb").read

        expect(source).not_to include('required_qualification_fields')
        expect(source).not_to include('custom_attributes[field]')
        expect(source).not_to match(/lead_state\.(fields|status|qualification_status)\b/)
        expect(source).not_to include("['status']")
      end
    end
  end
end
