# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Commercial::EscalationService do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:contact) { create(:contact, account: account, name: 'Ana Souza') }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:message) { create(:message, account: account, conversation: conversation, message_type: :incoming, content: 'Quero falar com alguém') }
  let!(:turn) { ScanSolo::AiTurn.create!(message: message, conversation: conversation, correlation_id: SecureRandom.uuid) }
  let(:stage) { :qualificado }
  let(:email_redirect_count) { 1 }
  let(:quote_sent_at) { 1.day.ago }
  let!(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: stage,
                                          email_redirect_count: email_redirect_count)
  end
  let!(:quote_request) do
    ScanSolo::QuoteRequest.create!(account: account, opportunity: opportunity, correlation_id: SecureRandom.uuid, sent_at: quote_sent_at)
  end
  let(:success) { ScanSolo::Notifications::Publisher::Result.new(success: true, reason: nil) }

  before do
    allow(ScanSolo::Notifications::EmailAdapter).to receive(:call).and_return(success)
    allow(ScanSolo::Notifications::Publisher).to receive(:call).and_call_original
  end

  def escalate(reason: 'negociacao', on: opportunity, with_turn: turn)
    ActiveRecord::Base.transaction { described_class.call(opportunity: on, reason: reason, turn: with_turn) }
  end

  def escalation_events
    ScanSolo::AuditEvent.where(subject: opportunity, event_type: 'commercial.escalated')
  end

  def refusal_events
    ScanSolo::AuditEvent.where(subject: opportunity, event_type: 'commercial.escalation_refused')
  end

  def other_turn
    other_message = create(:message, account: account, conversation: conversation, message_type: :incoming, content: 'Quero um humano')
    ScanSolo::AiTurn.create!(message: other_message, conversation: conversation, correlation_id: SecureRandom.uuid)
  end

  it 'writes the mark, records the audit without a phone and returns the CT-01 approved result' do
    freeze_time do
      result = escalate(reason: 'duvida_proposta')

      expect(result).to eq(escalated: true, reason: 'duvida_proposta', escalated_at: Time.current.iso8601)
      expect(opportunity.reload).to have_attributes(escalated_to_commercial_at: Time.current, escalation_reason: 'duvida_proposta')
    end

    event = escalation_events.sole
    expect(event.correlation_id).to eq(turn.correlation_id)
    expect(event.payload).to eq('reason' => 'duvida_proposta', 'conversation_id' => conversation.id,
                                'message_id' => message.id, 'stage' => 'qualificado')
  end

  it 'escalates at most once per turn correlation id' do
    escalate
    escalate(reason: 'pedido_humano')

    expect(escalation_events.count).to eq(1)
    expect(opportunity.reload.escalation_reason).to eq('negociacao')
    expect(ScanSolo::Notifications::Publisher).to have_received(:call).once
  end

  it 'overwrites the mark on a later escalation from another turn and keeps both events (RF-09)' do
    escalate
    later = 2.hours.from_now.change(usec: 0)

    travel_to(later) { escalate(reason: 'pedido_humano', with_turn: other_turn) }

    expect(opportunity.reload).to have_attributes(escalation_reason: 'pedido_humano', escalated_to_commercial_at: later)
    expect(escalation_events.count).to eq(2)
  end

  ScanSolo::PipelineOpportunity::ESCALATION_REASONS.each do |reason|
    it "publishes 1 notice after commit with the turn correlation id and the reason #{reason} (RF-23)" do
      ActiveRecord::Base.transaction do
        described_class.call(opportunity: opportunity, reason: reason, turn: turn)
        expect(ScanSolo::Notifications::Publisher).not_to have_received(:call)
      end

      expected = ScanSolo::Notifications::NegotiationPayload.build(
        opportunity: opportunity.reload, trigger_message: message, correlation_id: turn.correlation_id
      )
      expect(ScanSolo::Notifications::Publisher).to have_received(:call).once do |event:, payload:|
        expect(event).to eq('commercial.escalated')
        expect(payload[:escalation_reason]).to eq(reason)
        expect(payload.except(:escalation_reason)).to eq(expected)
      end
      expect(ScanSolo::AuditEvent.where(event_type: 'negotiation.notification_sent', correlation_id: turn.correlation_id).count).to eq(1)
    end
  end

  context 'when the opportunity is already escalated in negociacao' do
    let(:stage) { :negociacao }

    before { opportunity.update!(escalated_to_commercial_at: 1.day.ago, escalation_reason: 'duvida_proposta') }

    it 'overwrites the columns and records 1 new event without a notice' do
      freeze_time do
        escalate(reason: 'pedido_humano')

        expect(opportunity.reload).to have_attributes(escalation_reason: 'pedido_humano', escalated_to_commercial_at: Time.current)
      end
      expect(escalation_events.count).to eq(1)
      expect(ScanSolo::Notifications::Publisher).not_to have_received(:call)
    end
  end

  context 'when the mark is present but the opportunity is ganho' do
    let(:stage) { :ganho }

    before { opportunity.update!(escalated_to_commercial_at: 1.day.ago, escalation_reason: 'negociacao') }

    it 'refuses by stage, keeps the old mark and publishes nothing' do
      expect(escalate).to eq(escalated: false, refusal: 'etapa_nao_qualificada', email_redirect_count: 1)
      expect(opportunity.reload.escalation_reason).to eq('negociacao')
      expect(ScanSolo::Notifications::Publisher).not_to have_received(:call)
    end
  end

  it 'decides the first escalation after the row lock, not on the stale in-memory object' do
    stale = ScanSolo::PipelineOpportunity.find(opportunity.id)
    ScanSolo::PipelineOpportunity.find(opportunity.id).update!(escalated_to_commercial_at: 1.hour.ago, escalation_reason: 'negociacao')

    escalate(on: stale)

    expect(ScanSolo::Notifications::Publisher).not_to have_received(:call)
  end

  context 'when the stage is not qualified (RF-01)' do
    let(:email_redirect_count) { 0 }
    let(:stage) { :em_contato }

    %i[novo_lead em_contato em_qualificacao].each do |unqualified|
      context "with stage #{unqualified}" do
        let(:stage) { unqualified }

        it 'refuses without writing the mark, keeps the counter and publishes nothing' do
          result = escalate(reason: 'assunto_orcamento')

          expect(result).to eq(escalated: false, refusal: 'etapa_nao_qualificada', email_redirect_count: 0)
          expect(opportunity.reload).to have_attributes(escalated_to_commercial_at: nil, escalation_reason: nil, email_redirect_count: 0)
          expect(escalation_events.count).to eq(0)
          expect(ScanSolo::Notifications::Publisher).not_to have_received(:call)
        end
      end
    end

    it 'records 1 refusal audit without a phone' do
      escalate(reason: 'pedido_humano')

      event = refusal_events.sole
      expect(event.correlation_id).to eq(turn.correlation_id)
      expect(event.payload).to eq('refusal' => 'etapa_nao_qualificada', 'stage' => 'em_contato', 'email_redirect_count' => 0,
                                  'reason' => 'pedido_humano', 'conversation_id' => conversation.id, 'message_id' => message.id)
      expect(event.payload.to_json).not_to include('5511')
    end
  end

  context 'when the quote request was not sent (RF-03)' do
    let(:email_redirect_count) { 0 }
    let(:quote_sent_at) { nil }

    it 'refuses without writing the mark, keeps the counter and publishes nothing' do
      result = escalate

      expect(result).to eq(escalated: false, refusal: 'orcamento_nao_enviado', email_redirect_count: 0)
      expect(opportunity.reload).to have_attributes(escalated_to_commercial_at: nil, email_redirect_count: 0)
      expect(ScanSolo::Notifications::Publisher).not_to have_received(:call)
    end

    it 'refuses the same way without any quote request' do
      quote_request.destroy!

      expect(escalate).to eq(escalated: false, refusal: 'orcamento_nao_enviado', email_redirect_count: 0)
    end
  end

  context 'when it is the first request after the quote was sent (RF-04)' do
    let(:email_redirect_count) { 0 }

    it 'increments the counter once, records the refusal and publishes nothing' do
      result = escalate

      expect(result).to eq(escalated: false, refusal: 'primeiro_pedido_email', email_redirect_count: 1)
      expect(opportunity.reload).to have_attributes(escalated_to_commercial_at: nil, email_redirect_count: 1)
      expect(refusal_events.sole.payload).to include('refusal' => 'primeiro_pedido_email', 'email_redirect_count' => 1)
      expect(escalation_events.count).to eq(0)
      expect(ScanSolo::Notifications::Publisher).not_to have_received(:call)
    end

    it 'returns the same refusal on a 2nd call in the same turn without incrementing again' do
      first = escalate
      second = escalate(reason: 'pedido_humano')

      expect(second).to eq(first)
      expect(opportunity.reload).to have_attributes(escalated_to_commercial_at: nil, email_redirect_count: 1)
      expect(refusal_events.count).to eq(1)
    end

    it 'approves the insistence on a later turn (RF-05)' do
      escalate
      escalate(with_turn: other_turn)

      expect(opportunity.reload.escalated_to_commercial_at).to be_present
      expect(escalation_events.count).to eq(1)
      expect(ScanSolo::Notifications::Publisher).to have_received(:call).once
    end

    it 'leaves the counter and the refusal audit untouched when the wrapping transaction rolls back' do
      ActiveRecord::Base.transaction do
        described_class.call(opportunity: opportunity, reason: 'negociacao', turn: turn)
        raise ActiveRecord::Rollback
      end

      expect(opportunity.reload.email_redirect_count).to eq(0)
      expect(refusal_events.count).to eq(0)
    end
  end

  it 'leaves no mark, no event and no notice when the wrapping transaction rolls back (RF-09)' do
    ActiveRecord::Base.transaction do
      described_class.call(opportunity: opportunity, reason: 'negociacao', turn: turn)
      raise ActiveRecord::Rollback
    end

    expect(opportunity.reload).to have_attributes(escalated_to_commercial_at: nil, escalation_reason: nil)
    expect(escalation_events.count).to eq(0)
    expect(ScanSolo::Notifications::Publisher).not_to have_received(:call)
  end
end
