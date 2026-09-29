# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Handoff::HandoffService do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:contact) { create(:contact, account: account, custom_attributes: { 'objections' => 'preço alto' }) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let!(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :em_qualificacao)
  end
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:writer) { ScanSolo::LeadState::Writer.new(lead_state: opportunity.lead_state) }

  before do
    draft = ScanSolo::AiAgentConfig.draft_for!(account)
    draft.update!(name: 'Agente', enabled: true, required_qualification_fields: ['Área'],
                  allowed_inbox_ids: [conversation.inbox_id])
    ScanSolo::AiAgent::PublishService.new(account: account).call
    create(:message, account: account, conversation: conversation, message_type: :incoming, sender: contact,
                     content: 'Quero saber mais sobre o produto')
  end

  describe '.call' do
    it 'creates exactly one private note with all nine required elements', :aggregate_failures do
      writer.apply_field!(key: 'area', value: '800 m²', status: 'confirmado', source_message_id: nil)
      described_class.call(conversation: conversation, reason: 'Cliente pediu para falar com humano', actor: agent)

      notes = conversation.messages.where(private: true)
      expect(notes.count).to eq(1)

      content = notes.last.content
      expect(content).to include('Motivo da transferência: Cliente pediu para falar com humano')
      expect(content).to include('Resumo:')
      expect(content).to include('Objetivo do cliente:')
      expect(content).to include('Campos de qualificação coletados: Área: 800 m²')
      expect(content).to include('Objeções: preço alto')
      expect(content).to include('Etapa do pipeline: Em Qualificação')
      expect(content).to include('Status da proposta: não aplicável')
      expect(content).to include('Ações pendentes:')
      expect(content).to include('Próximo passo recomendado:')
    end

    context 'with config v2, data confirmed in the lead state and data only in the Contact (RF-16; lead state RF-08)' do
      let(:contact) do
        create(:contact, account: account, email: 'lead@example.com',
                         custom_attributes: { 'cidade_uf' => 'Rio/RJ', 'objections' => 'preço alto' })
      end

      before do
        draft = ScanSolo::AiAgentConfig.draft_for!(account)
        draft.update!(required_qualification_fields: ['Objetivo do serviço', 'Cidade / UF', 'Prazo desejado', 'E-mail'])
        ScanSolo::AiAgent::PublishService.new(account: account).call
        writer.apply_field!(key: 'email', value: 'lead@example.com', status: 'confirmado', source_message_id: nil)
        writer.apply_field!(key: 'prazo_desejado', value: 'amanhã', status: 'confirmado', source_message_id: nil)
      end

      it 'lists only the confirmed fields in config order and keeps the other eight lines unchanged' do
        described_class.call(conversation: conversation, reason: 'transferência', actor: agent)

        expect(conversation.messages.where(private: true).last.content.lines(chomp: true)).to eq(
          [
            'Motivo da transferência: transferência',
            'Resumo: Cliente: Quero saber mais sobre o produto',
            'Objetivo do cliente: não informado',
            'Campos de qualificação coletados: Prazo desejado: amanhã, E-mail: lead@example.com',
            'Objeções: preço alto',
            'Etapa do pipeline: Em Qualificação',
            'Status da proposta: não aplicável',
            'Ações pendentes: nenhuma',
            'Próximo passo recomendado: Revisar o histórico da conversa e responder diretamente ao cliente.'
          ]
        )
      end
    end

    it 'shows the pt-BR label of the current proposal version status (RF-21)' do
      proposal = ScanSolo::Proposal.create!(opportunity: opportunity)
      proposal.versions.create!(status: :generated)

      described_class.call(conversation: conversation, reason: 'transferência', actor: agent)

      expect(conversation.messages.where(private: true).last.content).to include('Status da proposta: Gerada')
    end

    it 'suppresses further automatic AI replies by moving control state away from ai_active' do
      described_class.call(conversation: conversation, reason: 'transferência', actor: agent)

      extension = ScanSolo::ConversationExtension.resolve_for(conversation)
      expect(extension).to be_awaiting_human
      expect(extension).not_to be_ai_active
    end

    it 'produces zero further AI-authored replies on a subsequent inbound message until an authorized return to AI' do
      described_class.call(conversation: conversation, reason: 'transferência', actor: agent)

      message = create(:message, account: account, conversation: conversation, message_type: :incoming, sender: contact, content: 'Mais uma pergunta')
      ScanSolo::AiTurnJob.new.perform(message.id)

      turn = ScanSolo::AiTurn.find_by(message_id: message.id)
      expect(turn).to have_attributes(invocation_status: 'suppressed', failure_reason: 'human_controlled')
      expect(conversation.messages.outgoing.where(private: false).count).to eq(0)
    end

    it 'does not create a duplicate note when called again while already awaiting_human' do
      described_class.call(conversation: conversation, reason: 'primeira solicitação', actor: agent)

      expect do
        described_class.call(conversation: conversation, reason: 'segunda solicitação', actor: agent)
      end.not_to(change { conversation.messages.where(private: true).count })
    end

    it 'still creates the note when the conversation already has the bare handoff_requested flag set (model-initiated path)' do
      ScanSolo::ConversationExtension.resolve_for(conversation).update!(ai_control_state: :handoff_requested)

      described_class.call(conversation: conversation, reason: 'solicitado pelo modelo', actor: nil)

      expect(conversation.messages.where(private: true).count).to eq(1)
      expect(ScanSolo::ConversationExtension.resolve_for(conversation)).to be_awaiting_human
    end

    it 'is a no-op once the conversation is already human_active' do
      ScanSolo::ConversationExtension.resolve_for(conversation).update!(ai_control_state: :human_active)

      expect do
        described_class.call(conversation: conversation, reason: 'tentativa tardia', actor: agent)
      end.not_to(change { conversation.messages.where(private: true).count })
    end
  end
end
