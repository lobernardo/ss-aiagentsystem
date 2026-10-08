# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Quote::EmailComposer do
  let(:block_labels) { ['Valor total:', 'Prazo/cronograma:', 'Escopo/atividades:', 'Condições de pagamento:', 'Observações comerciais:'] }
  let(:empty_block) { ['=== RESPOSTA DO ORÇAMENTO ===', *block_labels, '=== FIM ==='].join("\n") }

  describe '.request (RF-13)' do
    let(:account) { create(:account) }
    let(:owner) { create(:user, account: account, name: 'Bruna Lima') }
    let(:contact) { create(:contact, account: account, name: 'Ana Souza', phone_number: '+5511987654321', email: 'ana@example.com') }
    let(:conversation) { create(:conversation, account: account, contact: contact) }
    let(:opportunity) do
      ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :qualificado,
                                            lead_source: 'manual', owner: owner)
    end
    let(:writer) { ScanSolo::LeadState::Writer.new(lead_state: opportunity.lead_state) }
    let(:config) { ScanSolo::AiAgentConfig.new(required_qualification_fields: ['Área']) }
    let(:projection) { ScanSolo::LeadState::Projection.call(opportunity: opportunity.reload, config: config) }
    let(:email) { described_class.request(opportunity: opportunity, projection: projection) }

    before do
      writer.apply_field!(key: 'empresa', value: 'Solar <Ltda>', status: 'confirmado', source_message_id: nil)
      writer.apply_field!(key: 'area', value: '800 m²', status: 'confirmado', source_message_id: nil)
      writer.apply_field!(key: 'cidade_uf', value: 'Campinas/SP', status: 'inferido', source_message_id: nil)
    end

    it 'composes the subject, identification, collected fields and the empty CT-04 block' do
      with_modified_env FRONTEND_URL: 'https://app.example.com' do
        expect(email.subject).to eq("Solicitação de orçamento ##{opportunity.id} — Solar <Ltda>")
        expect(email.text).to include(
          "Oportunidade: ##{opportunity.id}", 'Nome: Ana Souza', 'Empresa: Solar <Ltda>', 'Telefone: +5511987654321',
          'E-mail: ana@example.com', 'Origem: Comercial', 'Responsável: Bruna Lima', 'Etapa: Qualificado',
          "https://app.example.com/app/accounts/#{account.id}/conversations/#{conversation.display_id}",
          'Empresa / razão social: Solar <Ltda>', 'Área: 800 m²', 'Cidade / UF: Campinas/SP (a confirmar)', empty_block
        )
      end
    end

    it 'marks only inferido fields, skips faltante fields and renders no secret' do
      fields = projection.blocks.values.flatten.reject { |field| field[:status] == 'faltante' }
      inferred, confirmed = fields.partition { |field| field[:status] == 'inferido' }

      expect(email.text.scan('(a confirmar)').size).to eq(inferred.size)
      inferred.each { |field| expect(email.text).to include("#{field[:label]}: #{field[:value]} (a confirmar)") }
      confirmed.each { |field| expect(email.text).to include("#{field[:label]}: #{field[:value]}\n") }
      expect(email.text).not_to include('Profundidade de investigação', 'api_access_token')
      expect(email.text.index('Identificação')).to be < email.text.index('Dados coletados')
      expect(email.text.index('Dados coletados')).to be < email.text.index('=== RESPOSTA DO ORÇAMENTO ===')
    end

    it 'breaks HTML lines with <br> and escapes values' do
      expect(email.html).to include('Nome: Ana Souza<br>Empresa: Solar &lt;Ltda&gt;<br>')
      expect(email.html).to include(block_labels.join('<br>'))
      expect(email.html).not_to include('<Ltda>')
    end
  end

  describe '.correction (RF-18)' do
    it 'lists each problem by its CT-04 label and repeats the empty block' do
      email = described_class.correction(problems: [:payment_terms])

      expect(email.text).to include('Condições de pagamento: ausente ou inválido', empty_block)
      expect(email.text).not_to include('Valor total: ausente')
      expect(email.html).to include('<br>=== RESPOSTA DO ORÇAMENTO ===<br>')
    end
  end

  describe '.negotiation (RF-37)' do
    let(:payload) do
      {
        account_id: 1, opportunity_id: 42, conversation_id: 7, conversation_url: 'https://app.example.com/app/accounts/1/conversations/9',
        contact: { name: 'Ana Souza', company: 'Solar Ltda', phone: '+5511987654321' }, stage: 'negociacao',
        request_summary: 'Consegue 10% de desconto?',
        proposal: { version_number: 2, proposal_number: 'SS-2026-000012', status: 'sent', document_url: 'https://app.example.com/pdf' },
        current_value: { amount: BigDecimal(12_500), currency: 'BRL' },
        recent_messages: [{ sender: 'customer', content: 'Recebi a proposta', created_at: '2026-10-01T12:00:00Z' },
                          { sender: 'agent', content: 'Ótimo!', created_at: '2026-10-01T12:01:00Z' }],
        correlation_id: 'abc'
      }
    end

    it 'renders the 9 items and the conversation link' do
      email = described_class.negotiation(payload: payload)

      expect(email.subject).to eq('Pedido de negociação #42 — Solar Ltda')
      expect(email.text).to include(
        'Nome: Ana Souza', 'Empresa: Solar Ltda', 'Telefone: +5511987654321', 'Oportunidade: #42', 'Etapa: Negociação',
        'Conversa no Chatwoot: https://app.example.com/app/accounts/1/conversations/9', 'Resumo do pedido: Consegue 10% de desconto?',
        'Proposta vigente: Versão 2, número SS-2026-000012, status sent, PDF: https://app.example.com/pdf',
        'Valor vigente: BRL 12.500,00', 'Últimas mensagens:', 'Cliente: Recebi a proposta', 'Atendimento: Ótimo!'
      )
      expect(email.html).to include('<br>')
    end

    it 'says "sem proposta" without a current proposal' do
      email = described_class.negotiation(payload: payload.merge(proposal: nil, current_value: nil))

      expect(email.text).to include('Proposta vigente: sem proposta', 'Valor vigente: sem proposta')
    end
  end

  describe 'proposal e-mails (CT-05, CT-06)' do
    let(:account) { create(:account) }
    let(:contact) { create(:contact, account: account, name: 'Ana <Souza>', email: 'ana@example.com') }
    let(:opportunity) do
      ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, stage: :qualificado,
                                            conversation: create(:conversation, account: account, contact: contact))
    end
    let(:version) do
      ScanSolo::Proposal.create!(opportunity: opportunity).versions.create!(
        generate_correlation_id: SecureRandom.uuid, status: :awaiting_approval, value: BigDecimal('12500.5'), currency: 'BRL'
      )
    end
    let(:proposals_url) { "https://app.example.com/app/accounts/#{account.id}/scansolo/proposals" }
    let(:lead_email_missing) { 'Atenção: falta e-mail do lead. Cadastre um e-mail válido no lead antes de aprovar.' }

    before do
      ScanSolo::LeadState::Writer.new(lead_state: opportunity.lead_state)
                                 .apply_field!(key: 'empresa', value: 'Solar & Cia', status: 'confirmado', source_message_id: nil)
    end

    describe '.approval_request' do
      let(:email) { with_modified_env(FRONTEND_URL: 'https://app.example.com') { described_class.approval_request(proposal_version: version) } }

      it 'renders number, version, value, lead, the Propostas link and the screen-only approval sentence in text and HTML' do
        expect(email.text).to include(
          "Número da proposta: #{version.proposal_number}", 'Versão: 1', 'Valor: BRL 12.500,50', 'Lead: Ana <Souza> — Solar & Cia',
          "Aprovar ou rejeitar na tela de Propostas: #{proposals_url}",
          'A aprovação só vale pela tela de Propostas. Responder este e-mail não aprova nem rejeita a proposta.'
        )
        expect(email.html).to include(version.proposal_number, 'Versão: 1', 'Valor: BRL 12.500,50', proposals_url)
        expect(email.text).not_to include(lead_email_missing)
      end

      it 'escapes values in the HTML' do
        expect(email.html).to include('Lead: Ana &lt;Souza&gt; — Solar &amp; Cia')
        expect(email.html).not_to include('<Souza>')
      end

      it 'warns that the lead e-mail is missing (RF-08)' do
        contact.update!(email: nil)

        expect(email.text).to include(lead_email_missing)
        expect(email.html).to include(lead_email_missing)
      end

      it 'renders no token or API URL (RNF-09)' do
        expect(email.text).not_to match(/api_access_token|Bearer|hook\.make|secret/)
      end
    end

    describe '.lead_proposal' do
      let(:email) { with_modified_env(FRONTEND_URL: 'https://app.example.com') { described_class.lead_proposal(proposal_version: version) } }

      it 'puts the proposal number in the subject and no URL in the body' do
        expect(email.subject).to eq("Sua proposta #{version.proposal_number}")
        expect(email.text).to include('Olá, Ana <Souza>!', "Número da proposta: #{version.proposal_number}")
        expect(email.text).not_to match(%r{https?://})
        expect(email.html).not_to match(%r{https?://})
        expect(email.html).to include('Olá, Ana &lt;Souza&gt;!')
      end
    end
  end
end
