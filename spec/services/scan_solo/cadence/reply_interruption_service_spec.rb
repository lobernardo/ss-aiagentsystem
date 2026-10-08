# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Cadence::ReplyInterruptionService do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :em_qualificacao)
  end
  let(:definition) { ScanSolo::CadenceDefinition.create!(stage: 'em_qualificacao', version: 1, offsets: [24, 48, 72]) }
  let!(:enrollment) do
    travel_to(1.hour.ago) { ScanSolo::Cadence::EnrollmentService.call(opportunity: opportunity, cadence_definition: definition) }
  end
  let(:interruptions) { ScanSolo::AuditEvent.where(event_type: described_class::EVENT_TYPE) }

  def incoming
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, sender: contact)
  end

  def outgoing
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                     additional_attributes: { 'scansolo_origin' => 'ai' })
  end

  def reply(message)
    described_class.call(opportunity: opportunity, message: message)
  end

  def results
    enrollment.attempts.order(:scheduled_at).pluck(:result)
  end

  it 'cancels the next scheduled attempt and records one audit with the enrollment, attempt and message' do
    first_attempt = enrollment.attempts.order(:scheduled_at).first
    message = incoming

    reply(message)

    expect(results).to eq(%w[cancelled scheduled scheduled])
    expect(enrollment.reload).to be_active
    expect(interruptions.sole).to have_attributes(
      subject: enrollment,
      payload: { 'enrollment_id' => enrollment.id, 'attempt_id' => first_attempt.id, 'message_id' => message.id }
    )
  end

  it 'cancels once for a burst of 3 replies with no outgoing message, keeping scheduled_at and sent attempts intact' do
    sent_attempt = enrollment.attempts.order(:scheduled_at).first
    ScanSolo::Cadence::AttemptEvidenceRecorder.record_sent!(sent_attempt)
    scheduled_at = enrollment.attempts.order(:scheduled_at).pluck(:scheduled_at)

    3.times { reply(incoming) }

    expect(results).to eq(%w[sent cancelled scheduled])
    expect(enrollment.attempts.order(:scheduled_at).pluck(:scheduled_at)).to eq(scheduled_at)
    expect(interruptions.count).to eq(1)
  end

  it 'starts a new cycle after a non-private outgoing message (customer -> outgoing -> customer = 2 cancellations)' do
    reply(incoming)
    travel(1.minute)
    outgoing
    travel(1.minute)
    reply(incoming)

    expect(results).to eq(%w[cancelled cancelled scheduled])
    expect(interruptions.count).to eq(2)
  end

  it 'does not start a new cycle on a private note' do
    reply(incoming)
    travel(1.minute)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, private: true)
    travel(1.minute)
    reply(incoming)

    expect(results).to eq(%w[cancelled scheduled scheduled])
  end

  it 'leaves an enrollment created after the message untouched' do
    message = travel_to(2.hours.ago) { incoming }

    reply(message)

    expect(results).to eq(%w[scheduled scheduled scheduled])
    expect(interruptions).to be_none
  end

  describe 'in proposta_enviada (RF-18)' do
    before { opportunity.update!(stage: :proposta_enviada) }

    it 'cancels every scheduled attempt with one audit per attempt' do
      message = incoming

      reply(message)

      expect(results).to eq(%w[cancelled cancelled cancelled])
      expect(interruptions.count).to eq(3)
      expect(interruptions.map { |audit| audit.payload['attempt_id'] }).to match_array(enrollment.attempts.ids)
      expect(interruptions.map { |audit| audit.payload['message_id'] }.uniq).to eq([message.id])
    end

    it 'keeps a sent attempt unchanged' do
      ScanSolo::Cadence::AttemptEvidenceRecorder.record_sent!(enrollment.attempts.order(:scheduled_at).first)

      reply(incoming)

      expect(results).to eq(%w[sent cancelled cancelled])
      expect(interruptions.count).to eq(2)
    end

    it 'cancels nothing new on a 2nd message' do
      reply(incoming)
      travel(1.minute)
      outgoing
      travel(1.minute)

      expect { reply(incoming) }.not_to change(interruptions, :count)
    end
  end

  it 'cancels only 1 of 3 scheduled attempts in em_contato (OC/RF-43)' do
    opportunity.update!(stage: :em_contato)

    reply(incoming)

    expect(results).to eq(%w[cancelled scheduled scheduled])
    expect(interruptions.count).to eq(1)
  end
end
