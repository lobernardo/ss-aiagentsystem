require 'rails_helper'

RSpec.describe ScanSolo::LeadState::Writer do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
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
      expect(lead_state.reload.fields).to eq({})
      expect(lead_state.events).to be_empty
    end

    it 'rejects a key outside the catalog' do
      expect { writer.apply_field!(key: 'budget', value: '10', status: 'confirmado', source_message_id: first_message.id) }
        .to raise_error(ArgumentError)
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

  describe '.applicable?' do
    it 'forbids only an inferido value over a confirmado one' do
      expect(described_class.applicable?(current_status: 'confirmado', new_status: 'inferido')).to be(false)
      expect(described_class.applicable?(current_status: 'confirmado', new_status: 'confirmado')).to be(true)
      expect(described_class.applicable?(current_status: 'inferido', new_status: 'confirmado')).to be(true)
      expect(described_class.applicable?(current_status: 'faltante', new_status: 'inferido')).to be(true)
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
