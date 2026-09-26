# frozen_string_literal: true

require 'rails_helper'

# RF-07 / RNF-06(4)(5): the six consumers of the "qualification field
# satisfied?" rule all delegate to ScanSolo::Qualification::FieldResolver, so
# for the same contact and published config they must agree on which labels
# are satisfied and which are missing -- including data stored under old or
# alternative labels (canonical key, config label, alias) and native columns.
RSpec.describe 'ScanSolo qualification consumer consistency' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:labels) do
    ['Nome', 'Objetivo do serviço', 'Cidade / UF', 'Endereço da obra', 'Área ou extensão', 'Profundidade de interesse',
     'Prazo desejado', 'Integração de segurança', 'Empresa', 'E-mail']
  end
  # Native name/email, one value under the canonical key, one under the exact
  # config label and the rest under old/alternative alias spellings.
  let(:contact) do
    create(:contact, account: account, name: 'Leonardo', email: 'leo@example.com',
                     custom_attributes: { 'tipo_intervencao' => 'Sondagem', 'Cidade / UF' => 'Rio/RJ', 'endereço' => 'Rua A 10',
                                          'ÁREA' => '800 m²', 'urgencia' => 'amanhã', 'objective' => 'obra nova' })
  end
  let(:expected_missing) { ['Profundidade de interesse', 'Integração de segurança', 'Empresa'] }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let!(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :em_qualificacao)
  end
  let(:message) do
    create(:message, account: account, conversation: conversation, message_type: :incoming, sender: contact, content: 'Olá')
  end

  let(:pipeline_context) do
    retrieval = ->(**) { { results: [], failure_reason: nil } }
    ScanSolo::AiTurn::ContextAssembler.call(message: message, config: ScanSolo::AiAgentConfig.published_for(account),
                                            retrieval_service: retrieval)[:pipeline_context]
  end
  let(:reply_completeness_missing) { ScanSolo::Cadence::ReplyCompletenessDetector.call(opportunity: opportunity).missing_fields }
  let(:generate_service_missing) do
    ScanSolo::Proposal::GenerateService.call(opportunity: opportunity, correlation_id: SecureRandom.uuid,
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
  # Make only carries the fixed canonical key set (RF-15): `integracao_seguranca`
  # is never sent, so its satisfaction is not observable through this consumer.
  let(:make_labels) do
    labels.select { |label| ScanSolo::Qualification::FieldResolver::MAKE_KEYS.include?(ScanSolo::Qualification::FieldResolver.canonical_key(label)) }
  end
  let(:make_satisfied) do
    payload = nil
    allow(ScanSolo::Make::OutboundRequestService).to receive(:call) { |**kwargs| payload = kwargs[:payload] }
    version = ScanSolo::Proposal.create!(opportunity: opportunity).versions.create!(generate_correlation_id: SecureRandom.uuid)
    ScanSolo::Proposal::MakeProvider.request_generation(proposal_version: version, correlation_id: version.generate_correlation_id)
    make_labels.select { |label| payload[:qualification].key?(ScanSolo::Qualification::FieldResolver.canonical_key(label)) }
  end

  before do
    draft = ScanSolo::AiAgentConfig.draft_for!(account)
    draft.update!(name: 'Agente', enabled: true, required_qualification_fields: labels, allowed_inbox_ids: [conversation.inbox_id])
    ScanSolo::AiAgent::PublishService.new(account: account).call
  end

  it 'derives identical satisfied and missing label sets from every consumer', :aggregate_failures do
    expected_satisfied = labels - expected_missing
    missing_by_consumer = {
      context_assembler: pipeline_context[:missing_fields],
      context_assembler_collected: labels - pipeline_context[:collected_fields].keys,
      reply_completeness_detector: reply_completeness_missing,
      generate_service: generate_service_missing,
      handoff_service: labels - handoff_satisfied
    }

    missing_by_consumer.each do |consumer, missing|
      expect(missing).to match_array(expected_missing), "#{consumer} missing: #{missing.inspect}"
      expect(labels - missing).to match_array(expected_satisfied), "#{consumer} satisfied: #{(labels - missing).inspect}"
    end
    expect(make_satisfied).to match_array(expected_satisfied & make_labels)
    expect(make_labels - make_satisfied).to match_array(expected_missing & make_labels)
  end

  it 'never lists data stored under old/alternative labels as missing in any consumer' do
    alias_labels = ['Objetivo do serviço', 'Endereço da obra', 'Área ou extensão', 'Prazo desejado']

    [pipeline_context[:missing_fields], reply_completeness_missing, generate_service_missing, labels - handoff_satisfied,
     make_labels - make_satisfied].each do |missing|
      expect(missing & alias_labels).to be_empty
    end
  end

  describe 'QualificationFieldAction (qualificado transition iff nothing is missing)' do
    let(:action_fields) { { 'profundidade' => '3 m', 'Integração de segurança' => 'NR-35', 'razão social' => 'ACME' } }

    it 'moves to qualificado exactly when the fields the other consumers report missing are supplied' do
      ScanSolo::Actions::QualificationFieldAction.call(params: { conversation_id: conversation.id, fields: action_fields })

      expect(opportunity.reload).to be_qualificado
      expect([pipeline_context[:missing_fields], reply_completeness_missing, generate_service_missing]).to all(be_empty)
    end

    it 'keeps em_qualificacao while any field the other consumers report missing is still unsatisfied' do
      ScanSolo::Actions::QualificationFieldAction.call(params: { conversation_id: conversation.id, fields: action_fields.except('razão social') })

      expect(opportunity.reload).to be_em_qualificacao
      expect([pipeline_context[:missing_fields], reply_completeness_missing, generate_service_missing]).to all(eq(['Empresa']))
    end
  end

  describe 'static single-reader check' do
    %w[
      ai_turn/context_assembler actions/qualification_field_action cadence/reply_completeness_detector
      proposal/generate_service proposal/make_provider handoff/handoff_service
    ].each do |consumer|
      it "keeps #{consumer} free of its own required-field presence rule" do
        source = Rails.root.join("app/services/scan_solo/#{consumer}.rb").read

        expect(source).not_to include('required_qualification_fields')
        expect(source).not_to include('custom_attributes[field]')
      end
    end
  end
end
