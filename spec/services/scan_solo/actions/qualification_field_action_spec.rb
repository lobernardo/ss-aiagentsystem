# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Actions::QualificationFieldAction do
  let(:account) { create(:account, scansolo_enabled: true) }
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
    described_class.call(params: { conversation_id: conversation.id, fields: fields })
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

  describe 'RF-16: all required qualification fields satisfied' do
    before { opportunity.update!(stage: :em_qualificacao) }

    it 'auto-transitions to qualificado once every required field is satisfied' do
      call(fields: { budget: '1000', timeline: '30 dias' })

      expect(opportunity.reload.stage).to eq('qualificado')
    end

    it 'leaves the stage unchanged when one required field is still missing' do
      call(fields: { budget: '1000' })

      expect(opportunity.reload.stage).to eq('em_qualificacao')
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

    it 'persists every accepted field of the call in a single contact update' do
      fields = { nome: 'Leonardo', cidade_uf: 'Rio/RJ', area: '800 m²', prazo_desejado: 'amanhã' }

      ActiveSupport::Notifications.subscribed(count_contact_updates, 'sql.active_record') { call(fields: fields) }

      collected = ScanSolo::Qualification::FieldResolver.call(contact: contact.reload, config: ScanSolo::AiAgentConfig.published_for(account))
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
      expect(ScanSolo::Qualification::FieldResolver.call(contact: contact, config: ScanSolo::AiAgentConfig.published_for(account))
                                                    .collected['Cidade / UF']).to eq('Macaé/RJ')
    end

    describe 'RF-10: native fields are never overwritten' do
      it 'keeps a present contact name and reports the key as not applied' do
        contact.update!(name: 'Milena (WhatsApp)')

        result = call(fields: { nome: 'Milena Souza' })

        expect(contact.reload.name).to eq('Milena (WhatsApp)')
        expect(result[:not_applied_fields]).to eq([{ field: 'nome', reason: 'native_already_present' }])
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
        correlation_id: 'corr-1', idempotency_key: 'idem-1'
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

    it 'moves to qualificado once when the only missing field is satisfied by a native value' do
      call(fields: { email: 'lead@example.com' })
      call(fields: { cidade_uf: 'Niterói/RJ' })

      expect(opportunity.reload.stage).to eq('qualificado')
      expect(opportunity.stage_events.where(to_stage: 'qualificado').count).to eq(1)
    end

    it 'leaves the stage unchanged while a required field is missing and the proposal gate still rejects' do
      contact.update!(custom_attributes: {})

      call(fields: { email: 'lead@example.com' })

      expect(opportunity.reload.stage).to eq('em_qualificacao')
      expect do
        ScanSolo::Proposal::GenerateService.call(opportunity: opportunity, correlation_id: 'corr-gate', provider: double)
      end.to raise_error(ActiveRecord::RecordInvalid, %r{Cidade / UF})
      expect(ScanSolo::ProposalVersion.count).to eq(0)
    end
  end
end
