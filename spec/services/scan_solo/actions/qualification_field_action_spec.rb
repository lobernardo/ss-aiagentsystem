# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Actions::QualificationFieldAction do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:message) { create(:message, account: account, conversation: conversation, message_type: :incoming) }
  let(:turn) { ScanSolo::AiTurn.create!(message: message, conversation: conversation, correlation_id: SecureRandom.uuid) }
  let(:lead_state) { opportunity.lead_state.reload }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }

  let(:required_fields) { %w[budget timeline] }
  let(:config_v2_labels) do
    ['Objetivo do serviço', 'Cidade / UF', 'Endereço da obra', 'Área ou extensão', 'Profundidade de interesse',
     'Prazo desejado', 'Integração de segurança', 'Empresa', 'E-mail']
  end

  let!(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :em_contato)
  end

  before do
    draft = ScanSolo::AiAgentConfig.draft_for!(account)
    draft.update!(name: 'Agente', enabled: true, required_qualification_fields: required_fields)
    ScanSolo::AiAgent::PublishService.new(account: account).call
  end

  def call(fields:)
    described_class.call(params: { conversation_id: conversation.id, fields: fields }, turn: turn)
  end

  def invoke(fields)
    ScanSolo::Actions::Registry.call(action_id: 'qualification_field', params: { conversation_id: conversation.id, fields: fields },
                                     correlation_id: turn.correlation_id, idempotency_key: SecureRandom.uuid, turn: turn)
  end

  describe 'RF-15: qualification interaction begins' do
    it 'moves an em_contato opportunity to em_qualificacao exactly once' do
      call(fields: { budget: '1000' })

      expect(opportunity.reload.stage).to eq('em_qualificacao')

      # A second invocation (still missing the "timeline" field) must not
      # re-trigger the em_contato -> em_qualificacao rule.
      expect(opportunity.stage_events.count).to eq(1)
      call(fields: { budget: '2000' })
      expect(opportunity.reload.stage).to eq('em_qualificacao')
      expect(opportunity.stage_events.count).to eq(1)
    end
  end

  describe 'lead state RF-21: completion is not this action' do
    let(:required_fields) { ['Área ou extensão', 'Cidade / UF'] }

    it 'moves em_contato to em_qualificacao on a required catalog key and never to qualificado' do
      call(fields: { area: '800 m²', cidade_uf: 'Rio/RJ' })

      expect(opportunity.reload.stage).to eq('em_qualificacao')
      expect(opportunity.stage_events.pluck(:to_stage)).to eq(['em_qualificacao'])
    end

    it 'keeps em_qualificacao when every required field becomes confirmado' do
      opportunity.update!(stage: :em_qualificacao)

      call(fields: { area: '800 m²', cidade_uf: 'Rio/RJ' })

      expect(opportunity.reload.stage).to eq('em_qualificacao')
      expect(opportunity.stage_events).to be_empty
    end
  end

  describe 'lead state RF-06/RF-07/RF-08: writes to the lead state and mirrors on the contact' do
    let(:required_fields) { ['Área ou extensão', 'Cidade / UF'] }
    let(:contact) { create(:contact, account: account, name: 'Milena (WhatsApp)', email: nil, phone_number: nil, custom_attributes: {}) }

    it 'writes a stated value as confirmado with the turn message as origin and mirrors it in custom_attributes' do
      result = invoke({ area: '800 m²' }).side_effect_result

      expect(lead_state.fields['area']).to include('value' => '800 m²', 'status' => 'confirmado', 'source_message_id' => message.id)
      expect(contact.reload.custom_attributes['area']).to eq('800 m²')
      expect(result[:state_changes]).to eq([{ key: 'area', outcome: :applied }])
    end

    it 'corrects the name in the lead state and keeps the native contact name' do
      result = call(fields: { nome: 'Milena Souza' })

      expect(lead_state.fields['nome']).to include('value' => 'Milena Souza', 'status' => 'confirmado')
      expect(lead_state.events.where(key: 'nome').order(:id).last)
        .to have_attributes(previous_value: 'Milena (WhatsApp)', previous_status: 'inferido', new_value: 'Milena Souza')
      expect(contact.reload.name).to eq('Milena (WhatsApp)')
      expect(result[:not_applied_fields]).to eq([{ field: 'nome', reason: 'native_already_present' }])
    end

    it 'writes a model-deduced value as inferido over a faltante field' do
      invoke({ cidade_uf: { value: 'RJ', status: 'inferido' } })

      expect(lead_state.fields['cidade_uf']).to include('value' => 'RJ', 'status' => 'inferido')
    end

    it 'keeps a confirmado value against an inferido one and reports confirmed_value_kept' do
      invoke({ cidade_uf: 'Rio/RJ' })

      result = invoke({ cidade_uf: { value: 'RJ', status: 'inferido' } }).side_effect_result

      expect(lead_state.fields['cidade_uf']).to include('value' => 'Rio/RJ', 'status' => 'confirmado')
      expect(contact.reload.custom_attributes['cidade_uf']).to eq('Rio/RJ')
      expect(result[:not_applied_fields]).to eq([{ field: 'cidade_uf', reason: 'confirmed_value_kept' }])
    end

    it 'rejects an entry that is neither a string nor a closed {value, status} object' do
      [{ x: { value: 1 } }, { area: { value: '800 m²' } }, { area: { value: '800 m²', status: 'faltante' } },
       { area: { value: '800 m²', status: 'confirmado', note: 'x' } }].each do |fields|
        expect { invoke(fields) }.to(raise_error { |error| expect(error.class.name).to eq('ScanSolo::Actions::Executor::InvalidParamsError') })
      end
      expect(lead_state.fields['area']['status']).to eq('faltante')
    end
  end

  describe 'allowed-fields filtering (RF-48)' do
    before { opportunity.update!(stage: :em_qualificacao) }

    it 'only persists fields present in the published required_qualification_fields allowlist' do
      call(fields: { budget: '1000', not_allowed: 'ignored' })

      expect(contact.reload.custom_attributes['budget']).to eq('1000')
      expect(contact.reload.custom_attributes).not_to have_key('not_allowed')
    end
  end

  describe 'RF-09: multi-field capture through aliases' do
    let(:required_fields) { ['Nome', *config_v2_labels] }
    let(:contact) { create(:contact, account: account, name: '') }
    let(:contact_updates) { [] }
    let(:count_contact_updates) do
      lambda do |*, payload|
        contact_updates << payload[:sql] if payload[:sql].start_with?('UPDATE "contacts"')
      end
    end

    # The turn's inbound message touches the contact on creation.
    before { turn }

    it 'persists every accepted field of the call in a single contact update' do
      fields = { nome: 'Leonardo', cidade_uf: 'Rio/RJ', area: '800 m²', prazo_desejado: 'amanhã' }

      ActiveSupport::Notifications.subscribed(count_contact_updates, 'sql.active_record') { call(fields: fields) }

      collected = ScanSolo::Qualification::FieldResolver.call(opportunity: opportunity.reload, config: ScanSolo::AiAgentConfig.published_for(account))
                                                        .collected
      expect(collected).to include('Nome' => 'Leonardo', 'Cidade / UF' => 'Rio/RJ', 'Área ou extensão' => '800 m²',
                                   'Prazo desejado' => 'amanhã')
      expect(contact_updates.size).to eq(1)
    end

    it 'accepts a native key outside the required list without driving a stage transition' do
      config = ScanSolo::AiAgentConfig.draft_for!(account)
      config.update!(required_qualification_fields: config_v2_labels)
      ScanSolo::AiAgent::PublishService.new(account: account).call

      result = call(fields: { nome: 'Leonardo' })

      expect(contact.reload.name).to eq('Leonardo')
      expect(result[:unrecognized_fields]).to be_empty
      expect(opportunity.reload.stage).to eq('em_contato')
    end

    it 'writes non-native fields under the canonical key without touching the existing label key (RF-21)' do
      contact.update!(custom_attributes: { 'Cidade / UF' => 'Niterói/RJ' })

      call(fields: { 'Cidade / UF': 'Macaé/RJ' })

      expect(contact.reload.custom_attributes).to eq('Cidade / UF' => 'Niterói/RJ', 'cidade_uf' => 'Macaé/RJ')
      expect(ScanSolo::Qualification::FieldResolver.call(opportunity: opportunity.reload, config: ScanSolo::AiAgentConfig.published_for(account))
                                                    .collected['Cidade / UF']).to eq('Macaé/RJ')
    end

    describe 'RF-10: native fields are never overwritten' do
      it 'keeps a present contact name and reports the key as not applied' do
        contact.update!(name: 'Milena (WhatsApp)')

        result = call(fields: { nome: 'Milena Souza' })

        expect(contact.reload.name).to eq('Milena (WhatsApp)')
        expect(result[:not_applied_fields]).to eq([{ field: 'nome', reason: 'native_already_present' }])
        expect(lead_state.fields['nome']).to include('value' => 'Milena Souza', 'status' => 'confirmado')
      end

      it 'writes the name when the native value is blank' do
        call(fields: { nome: 'Milena Souza' })

        expect(contact.reload.name).to eq('Milena Souza')
      end

      it 'drops an invalid native value, reports it and still saves the other fields in one update' do
        result = nil

        ActiveSupport::Notifications.subscribed(count_contact_updates, 'sql.active_record') do
          result = call(fields: { email: 'invalido', cidade_uf: 'Rio/RJ' })
        end

        expect(contact.reload.email).to be_blank
        expect(contact.custom_attributes['cidade_uf']).to eq('Rio/RJ')
        expect(result[:updated_fields]).to eq(['cidade_uf'])
        expect(result[:not_applied_fields]).to contain_exactly(hash_including(field: 'email', reason: be_present))
        expect(contact_updates.size).to eq(1)
      end
    end
  end

  describe 'RF-11: unrecognized keys' do
    let(:required_fields) { config_v2_labels }

    it 'does not persist the key and reports it in the result and in the audit event' do
      execution = ScanSolo::Actions::Registry.call(
        action_id: 'qualification_field', params: { conversation_id: conversation.id, fields: { cidade_uf: 'Rio/RJ', cor_favorita: 'azul' } },
        correlation_id: 'corr-1', idempotency_key: 'idem-1', turn: turn
      )

      expect(contact.reload.custom_attributes).to eq('cidade_uf' => 'Rio/RJ')
      expect(execution.side_effect_result[:unrecognized_fields]).to eq(['cor_favorita'])
      audit = ScanSolo::AuditEvent.find_by!(event_type: 'agent_action.qualification_field')
      expect(audit.payload.dig('result', 'unrecognized_fields')).to eq(['cor_favorita'])
    end
  end

  describe 'RF-12: stage transitions fed by the resolver' do
    let(:required_fields) { ['Cidade / UF', 'E-mail'] }
    let(:contact) { create(:contact, account: account, email: nil, custom_attributes: { 'cidade_uf' => 'Rio/RJ' }) }

    before { opportunity.update!(stage: :em_qualificacao) }

    it 'confirms a field that was only inferido from the contact without any stage transition' do
      call(fields: { email: 'lead@example.com' })
      call(fields: { cidade_uf: 'Niterói/RJ' })

      expect(lead_state.fields.values_at('email', 'cidade_uf').pluck('status')).to eq(%w[confirmado confirmado])
      expect(contact.reload.custom_attributes['cidade_uf']).to eq('Niterói/RJ')
      expect(opportunity.reload.stage).to eq('em_qualificacao')
    end

    it 'leaves the stage unchanged while a required field is missing and the proposal gate still rejects' do
      contact.update!(custom_attributes: {})

      call(fields: { email: 'lead@example.com' })

      expect(opportunity.reload.stage).to eq('em_qualificacao')
      # RF-25 (RNF-11): with the validated quote reply, the field gate is what rejects.
      quote_request = ScanSolo::QuoteRequest.create!(account: account, opportunity: opportunity, correlation_id: SecureRandom.uuid, status: :replied)
      expect do
        ScanSolo::Proposal::GenerateService.call(opportunity: opportunity, quote_request: quote_request, correlation_id: 'corr-gate',
                                                 provider: double)
      end.to raise_error(ActiveRecord::RecordInvalid, %r{Cidade / UF})
      expect(ScanSolo::ProposalVersion.count).to eq(0)
    end
  end
end
