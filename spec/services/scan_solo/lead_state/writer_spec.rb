require 'rails_helper'

RSpec.describe ScanSolo::LeadState::Writer do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, name: '') }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:opportunity) { ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation) }
  let(:lead_state) { ScanSolo::LeadState.find_or_create_by!(opportunity: opportunity) }
  let(:writer) { described_class.new(lead_state: lead_state) }
  let(:first_message) { create(:message, account: account, conversation: conversation, message_type: :incoming) }
  let(:second_message) { create(:message, account: account, conversation: conversation, message_type: :incoming) }

  describe '#apply_field!' do
    it 'makes a corrected value current as confirmado and keeps the previous value in history (RF-06)' do
      writer.apply_field!(key: 'tempo_integracao', value: 'uma diária', status: 'confirmado', source_message_id: first_message.id)

      outcome = writer.apply_field!(key: 'tempo_integracao', value: '30 minutos no mesmo dia', status: 'confirmado',
                                    source_message_id: second_message.id)

      expect(outcome).to eq(:applied)
      expect(lead_state.reload.fields['tempo_integracao']).to include('value' => '30 minutos no mesmo dia', 'status' => 'confirmado',
                                                                      'source_message_id' => second_message.id, 'source_attachment_id' => nil)
      expect(lead_state.reload.fields['tempo_integracao']['updated_at']).to be_present
      first_event, second_event = lead_state.events.order(:id).to_a
      expect(first_event).to have_attributes(subject: 'field', key: 'tempo_integracao', previous_value: nil, previous_status: 'faltante',
                                             new_value: 'uma diária', new_status: 'confirmado', source_message_id: first_message.id)
      expect(second_event).to have_attributes(previous_value: 'uma diária', previous_status: 'confirmado', new_value: '30 minutos no mesmo dia',
                                              new_status: 'confirmado', source_message_id: second_message.id)
    end

    it 'keeps a confirmado value when an inferido one arrives (RF-07)' do
      writer.apply_field!(key: 'cidade_uf', value: 'Rio/RJ', status: 'confirmado', source_message_id: first_message.id)

      outcome = writer.apply_field!(key: 'cidade_uf', value: 'RJ', status: 'inferido', source_message_id: second_message.id)

      expect(outcome).to eq(:kept_confirmed)
      expect(lead_state.reload.fields['cidade_uf']).to include('value' => 'Rio/RJ', 'status' => 'confirmado', 'source_message_id' => first_message.id)
      expect(lead_state.events.count).to eq(1)
    end

    it 'writes an inferido value over a missing field with its attachment origin' do
      outcome = writer.apply_field!(key: 'cidade_uf', value: 'RJ', status: 'inferido', source_message_id: first_message.id,
                                    source_attachment_id: 77)

      expect(outcome).to eq(:applied)
      expect(lead_state.reload.fields['cidade_uf']).to include('value' => 'RJ', 'status' => 'inferido', 'source_attachment_id' => 77)
      expect(lead_state.events.sole).to have_attributes(previous_status: 'faltante', new_status: 'inferido', source_attachment_id: 77)
    end

    it 'records one event when an inferido value is confirmed with the same value' do
      writer.apply_field!(key: 'cnpj', value: '12.345.678/0001-90', status: 'inferido', source_message_id: first_message.id)

      expect do
        writer.apply_field!(key: 'cnpj', value: '12.345.678/0001-90', status: 'confirmado', source_message_id: second_message.id)
      end.to change(ScanSolo::LeadStateEvent, :count).by(1)

      expect(lead_state.reload.fields['cnpj']).to include('status' => 'confirmado', 'source_message_id' => second_message.id)
      expect(lead_state.events.order(:id).last).to have_attributes(previous_value: '12.345.678/0001-90', previous_status: 'inferido',
                                                                   new_value: '12.345.678/0001-90', new_status: 'confirmado')
    end

    it 'reports the same value and status as unchanged without an event' do
      writer.apply_field!(key: 'area', value: '800 m²', status: 'confirmado', source_message_id: first_message.id)

      expect do
        expect(writer.apply_field!(key: 'area', value: ' 800 m² ', status: 'confirmado', source_message_id: second_message.id))
          .to eq(:unchanged)
      end.not_to change(ScanSolo::LeadStateEvent, :count)
    end

    it 'ignores a blank value' do
      expect(writer.apply_field!(key: 'area', value: '  ', status: 'confirmado', source_message_id: first_message.id)).to eq(:ignored)
      expect(lead_state.reload.fields['area']).to include('value' => nil, 'status' => 'faltante')
      expect(lead_state.events).to be_empty
    end

    it 'rejects a key outside the catalog' do
      expect { writer.apply_field!(key: 'budget', value: '10', status: 'confirmado', source_message_id: first_message.id) }
        .to raise_error(ArgumentError)
    end
  end

  describe 'RF-27 precedence with nao_informado' do
    def apply(status, value, message = second_message)
      writer.apply_field!(key: 'profundidade', value: value, status: status, source_message_id: message.id)
    end

    it 'replaces nao_informado with a confirmado value and records 1 event' do
      apply('nao_informado', 'não sei', first_message)

      expect { expect(apply('confirmado', '3 m')).to eq(:applied) }.to change(ScanSolo::LeadStateEvent, :count).by(1)
      expect(lead_state.reload.fields['profundidade']).to include('value' => '3 m', 'status' => 'confirmado')
      expect(lead_state.events.order(:id).last).to have_attributes(previous_value: 'não sei', previous_status: 'nao_informado',
                                                                   new_value: '3 m', new_status: 'confirmado')
    end

    it 'writes nao_informado over faltante with the lead words, its origin and 1 event' do
      expect { expect(apply('nao_informado', ' não sei ')).to eq(:applied) }.to change(ScanSolo::LeadStateEvent, :count).by(1)
      expect(lead_state.reload.fields['profundidade']).to include('value' => 'não sei', 'status' => 'nao_informado',
                                                                  'source_message_id' => second_message.id)
      expect(lead_state.events.sole).to have_attributes(previous_status: 'faltante', new_status: 'nao_informado')
    end

    it 'replaces inferido with nao_informado' do
      apply('inferido', '2 m', first_message)

      expect { expect(apply('nao_informado', 'não sei')).to eq(:applied) }.to change(ScanSolo::LeadStateEvent, :count).by(1)
      expect(lead_state.reload.fields['profundidade']).to include('value' => 'não sei', 'status' => 'nao_informado')
    end

    it 'keeps confirmado when nao_informado arrives, with 0 events' do
      apply('confirmado', '3 m', first_message)

      expect { expect(apply('nao_informado', 'não sei')).to eq(:kept_confirmed) }.not_to change(ScanSolo::LeadStateEvent, :count)
      expect(lead_state.reload.fields['profundidade']).to include('value' => '3 m', 'status' => 'confirmado', 'source_message_id' => first_message.id)
    end

    it 'keeps nao_informado when an inferido value arrives (action or attachment extraction), with 0 events' do
      apply('nao_informado', 'não sei', first_message)

      expect do
        expect(apply('inferido', '2 m')).to eq(:kept_not_informed)
        expect(writer.apply_field!(key: 'profundidade', value: '2 m', status: 'inferido', source_message_id: second_message.id,
                                   source_attachment_id: 77)).to eq(:kept_not_informed)
      end.not_to change(ScanSolo::LeadStateEvent, :count)
      expect(lead_state.reload.fields['profundidade']).to include('value' => 'não sei', 'status' => 'nao_informado')
    end

    it 'keeps confirmado when inferido arrives (current rule)' do
      apply('confirmado', '3 m', first_message)

      expect { expect(apply('inferido', '2 m')).to eq(:kept_confirmed) }.not_to change(ScanSolo::LeadStateEvent, :count)
      expect(lead_state.reload.fields['profundidade']).to include('value' => '3 m', 'status' => 'confirmado')
    end
  end

  describe '#record_collection_offer!' do
    it 'records the offer once, keeping the first instant and 1 event (RF-36)' do
      first_at = Time.zone.parse('2026-10-13 10:00:00.123456')

      expect(writer.record_collection_offer!(at: first_at, source_message_id: first_message.id)).to eq(:applied)
      expect(writer.record_collection_offer!(at: first_at + 1.hour, source_message_id: second_message.id)).to eq(:unchanged)

      expect(lead_state.reload.collection_offered_at).to eq(first_at)
      expect(lead_state.events.sole).to have_attributes(subject: 'collection_mode', key: 'collection_offered_at', previous_value: nil,
                                                        new_value: first_at.iso8601(6), source_message_id: first_message.id)
    end
  end

  describe '#set_collection_mode!' do
    it 'ignores a choice before the offer, with 0 events (RF-37)' do
      expect(writer.set_collection_mode!(mode: 'em_bloco', source_message_id: first_message.id)).to eq(:ignored)
      expect(lead_state.reload.collection_mode).to be_nil
      expect(lead_state.events).to be_empty
    end

    it 'records the choice once after the offer and never changes it (RF-37)' do
      writer.record_collection_offer!(at: Time.current, source_message_id: first_message.id)
      expect do
        expect(writer.set_collection_mode!(mode: 'em_bloco', source_message_id: second_message.id)).to eq(:applied)
      end.to change(ScanSolo::LeadStateEvent, :count).by(1)
      expect(lead_state.events.order(:id).last).to have_attributes(subject: 'collection_mode', key: 'collection_mode', new_value: 'em_bloco',
                                                                   source_message_id: second_message.id)

      expect do
        expect(writer.set_collection_mode!(mode: 'progressiva', source_message_id: second_message.id)).to eq(:ignored)
      end.not_to change(ScanSolo::LeadStateEvent, :count)
      expect(lead_state.reload.collection_mode).to eq('em_bloco')
    end

    it 'rejects a mode outside the list' do
      expect { writer.set_collection_mode!(mode: 'rapido', source_message_id: first_message.id) }.to raise_error(ArgumentError)
    end
  end

  describe '#set_intent!' do
    it 'records one event per intent change (RF-14)' do
      writer.set_intent!(intent: 'orcamento', source_message_id: first_message.id)
      writer.set_intent!(intent: 'convite_cotacao', source_message_id: second_message.id)

      expect(lead_state.reload.intent).to eq('convite_cotacao')
      expect(lead_state.events.order(:id).map { |event| [event.subject, event.previous_value, event.new_value, event.source_message_id] })
        .to eq([['intent', nil, 'orcamento', first_message.id], ['intent', 'orcamento', 'convite_cotacao', second_message.id]])
    end

    it 'does nothing when the intent is the same' do
      writer.set_intent!(intent: 'orcamento', source_message_id: first_message.id)

      expect(writer.set_intent!(intent: 'orcamento', source_message_id: second_message.id)).to eq(:unchanged)
      expect(lead_state.events.count).to eq(1)
    end

    it 'rejects an intent outside the list' do
      expect { writer.set_intent!(intent: 'xyz', source_message_id: first_message.id) }.to raise_error(ActiveRecord::RecordInvalid)
      expect(lead_state.events).to be_empty
    end
  end

  describe '#record_next_action!' do
    it 'records the next action with its origin and one event (RF-23)' do
      writer.record_next_action!(value: 'proposta', source_message_id: first_message.id)

      expect(lead_state.reload).to have_attributes(next_action: 'proposta', next_action_source_message_id: first_message.id)
      expect(lead_state.next_action_recorded_at).to be_present
      expect(lead_state.events.sole).to have_attributes(subject: 'next_action', previous_value: nil, new_value: 'proposta',
                                                        source_message_id: first_message.id)
    end

    it 'records a backfill next action with a nil origin' do
      writer.record_next_action!(value: 'aguardar_cliente', source_message_id: nil)

      expect(lead_state.reload).to have_attributes(next_action: 'aguardar_cliente', next_action_source_message_id: nil)
      expect(lead_state.events.sole).to have_attributes(subject: 'next_action', new_value: 'aguardar_cliente', source_message_id: nil)
    end

    it 'keeps previous next actions in history' do
      writer.record_next_action!(value: 'proposta', source_message_id: first_message.id)
      writer.record_next_action!(value: 'atendimento_humano', source_message_id: second_message.id)

      expect(lead_state.events.order(:id).pluck(:previous_value, :new_value)).to eq([[nil, 'proposta'], %w[proposta atendimento_humano]])
    end
  end

  describe '#authorize_action!' do
    it 'stores an authorization once and without history events (RF-24)' do
      writer.authorize_action!(action: 'proposta', source_message_id: first_message.id)
      writer.authorize_action!(action: 'proposta', source_message_id: second_message.id)

      expect(lead_state.reload.authorized_actions.size).to eq(1)
      expect(lead_state.authorized_actions.sole).to include('action' => 'proposta', 'source_message_id' => first_message.id)
      expect(lead_state.authorized_actions.sole['recorded_at']).to be_present
      expect(lead_state.events).to be_empty
    end

    it 'rejects an action outside the list' do
      expect { writer.authorize_action!(action: 'xyz', source_message_id: first_message.id) }.to raise_error(ArgumentError)
    end
  end

  describe '#revoke_action!' do
    it 'removes only the given authorization, without history events' do
      writer.authorize_action!(action: 'atendimento_humano', source_message_id: first_message.id)
      writer.authorize_action!(action: 'proposta', source_message_id: second_message.id)

      expect(writer.revoke_action!(action: 'atendimento_humano')).to eq(:applied)
      expect(lead_state.reload.authorized_actions.pluck('action')).to eq(['proposta'])
      expect(writer.revoke_action!(action: 'atendimento_humano')).to eq(:unchanged)
      expect(lead_state.events).to be_empty
    end

    it 'rejects an action outside the list' do
      expect { writer.revoke_action!(action: 'xyz') }.to raise_error(ArgumentError)
    end

    # Regression (a "specialist" request handed off): the wrong turn left atendimento_humano as next action and
    # authorized action, and the model kept copying it. Clearing both keeps the fields, history and AI state.
    it 'clears the residual atendimento_humano of a wrong handoff, keeping fields and history' do
      writer.apply_field!(key: 'cidade_uf', value: 'Joinville/SC', status: 'confirmado', source_message_id: second_message.id)
      writer.record_next_action!(value: 'atendimento_humano', source_message_id: first_message.id)
      writer.authorize_action!(action: 'atendimento_humano', source_message_id: first_message.id)

      writer.revoke_action!(action: 'atendimento_humano')
      writer.record_next_action!(value: nil, source_message_id: nil)

      projection = ScanSolo::LeadState::Projection.call(opportunity: opportunity.reload, config: nil)
      prompt = ScanSolo::AiTurn::LeadStatePrompt.call(lead_state_context: projection.to_h.merge(summary_allowed: false))['Estado do lead']
      expect(lead_state.reload).to have_attributes(next_action: nil, authorized_actions: [])
      expect(lead_state.fields['cidade_uf']).to include('value' => 'Joinville/SC', 'status' => 'confirmado')
      expect(lead_state.events.where(subject: 'next_action').pluck(:previous_value, :new_value))
        .to eq([[nil, 'atendimento_humano'], ['atendimento_humano', nil]])
      expect(prompt).to include("Próxima ação: nenhuma\nAções autorizadas (já pedidas ou autorizadas pelo cliente, não peça confirmação):\nnenhuma")
      expect(prompt).not_to include('atendimento_humano')
    end
  end

  describe '#complete!' do
    it 'completes once and raises on a second completion (RF-21)' do
      completed_at = Time.zone.parse('2026-09-29 10:00:00')

      writer.complete!(at: completed_at)

      expect(lead_state.reload).to be_concluida
      expect(lead_state.qualification_completed_at).to eq(completed_at)
      expect { writer.complete!(at: Time.current) }.to raise_error(ActiveRecord::RecordInvalid)
      expect(lead_state.reload.qualification_completed_at).to eq(completed_at)
    end
  end

  describe 'RF-14 (b): opening the quote request update window after commit' do
    let(:request_message) { create(:message, account: account, conversation: conversation, message_type: :outgoing) }

    before do
      ScanSolo::QuoteRequest.create!(account: account, opportunity: opportunity, correlation_id: SecureRandom.uuid,
                                     request_message_id: request_message.id)
    end

    def apply_depth(value = '3 m')
      writer.apply_field!(key: 'profundidade', value: value, status: 'confirmado', source_message_id: first_message.id)
    end

    it 'enqueues 1 update job once a change after the request e-mail is committed' do
      expect { ActiveRecord::Base.transaction { apply_depth } }.to have_enqueued_job(ScanSolo::QuoteRequestUpdateJob).exactly(:once)
    end

    it 'enqueues nothing when the transaction rolls back' do
      expect do
        ActiveRecord::Base.transaction do
          apply_depth
          raise ActiveRecord::Rollback
        end
      end.not_to have_enqueued_job(ScanSolo::QuoteRequestUpdateJob)
    end

    it 'enqueues nothing for an :unchanged field' do
      apply_depth
      clear_enqueued_jobs

      expect { expect(apply_depth).to eq(:unchanged) }.not_to have_enqueued_job(ScanSolo::QuoteRequestUpdateJob)
    end
  end

  describe '.applicable?' do
    it 'forbids inferido or nao_informado over confirmado and inferido over nao_informado (RF-07, RF-27)' do
      refused = [%w[confirmado inferido], %w[confirmado nao_informado], %w[nao_informado inferido]]
      accepted = [%w[nao_informado confirmado], %w[inferido nao_informado], %w[faltante nao_informado], %w[confirmado confirmado],
                  %w[inferido confirmado], %w[faltante inferido]]
      outcomes = (refused + accepted).map { |current, new| described_class.applicable?(current_status: current, new_status: new) }

      expect(outcomes).to eq(([false] * refused.size) + ([true] * accepted.size))
    end
  end

  it 'creates exactly one event per change (RNF-06)' do
    expect do
      writer.apply_field!(key: 'area', value: '800 m²', status: 'inferido', source_message_id: first_message.id)
      writer.apply_field!(key: 'area', value: '800 m²', status: 'confirmado', source_message_id: second_message.id)
      writer.apply_field!(key: 'area', value: '900 m²', status: 'confirmado', source_message_id: second_message.id)
      writer.set_intent!(intent: 'orcamento', source_message_id: first_message.id)
      writer.record_next_action!(value: 'proposta', source_message_id: second_message.id)
    end.to change(ScanSolo::LeadStateEvent, :count).by(5)
  end
end
