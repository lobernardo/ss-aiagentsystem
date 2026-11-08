# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Quote::HandledManuallyService do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:user) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:stage) { :qualificado }
  let(:opportunity) { ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: stage) }
  let(:quote_status) { :awaiting_reply }
  let!(:quote_request) do
    ScanSolo::QuoteRequest.create!(account: account, opportunity: opportunity, correlation_id: SecureRandom.uuid, status: quote_status)
  end
  let!(:post_proposal_definition) { ScanSolo::CadenceDefinition.create!(stage: 'proposta_enviada', version: 1, offsets: [24, 72, 168]) }
  let(:audits) { ScanSolo::AuditEvent.where(event_type: 'quote_request.handled_manually') }
  let(:post_proposal_enrollments) do
    ScanSolo::CadenceEnrollment.where(opportunity: opportunity, cadence_definition: ScanSolo::CadenceDefinition.where(stage: 'proposta_enviada'))
  end

  def handle(mode: 'single', target: ScanSolo::PipelineOpportunity.find(opportunity.id))
    described_class.call(opportunity: target, actor: user, mode: mode)
  end

  describe 'eligibility (RF-15)' do
    shared_examples 'a refusal without changes' do |code|
      it "raises #{code} and changes no row" do
        expect { handle }.to raise_error(CustomExceptions::ScanSolo::HandledManuallyRejected, code)
          .and not_change(ScanSolo::PipelineStageEvent, :count)
          .and(not_change(ScanSolo::AuditEvent, :count))
          .and(not_change(ScanSolo::CadenceEnrollment, :count))
          .and(not_change { quote_request.reload.attributes })
          .and(not_change { opportunity.reload.stage })
      end
    end

    context 'without a quote request' do
      before { quote_request.destroy! }

      it 'raises quote_request_missing and changes no row' do
        expect { handle }.to raise_error(CustomExceptions::ScanSolo::HandledManuallyRejected, 'quote_request_missing')
          .and not_change(ScanSolo::PipelineStageEvent, :count)
          .and(not_change(ScanSolo::AuditEvent, :count))
          .and(not_change { opportunity.reload.stage })
      end
    end

    %i[replied handled_manually].each do |status|
      context "with a #{status} request" do
        let(:quote_status) { status }

        it_behaves_like 'a refusal without changes', 'quote_request_closed'
      end
    end

    context 'with a stage other than qualificado or proposta_enviada' do
      let(:stage) { :em_qualificacao }

      it_behaves_like 'a refusal without changes', 'invalid_stage'
    end
  end

  describe 'accepted effects (RF-16, CT-07)' do
    it 'moves qualificado to proposta_enviada with the user, closes the request and records 1 audit' do
      freeze_time do
        handle

        event = ScanSolo::PipelineStageEvent.where(opportunity: opportunity).sole
        expect(event).to have_attributes(from_stage: 'qualificado', to_stage: 'proposta_enviada', actor: user)
        expect(opportunity.reload.stage).to eq('proposta_enviada')
        expect(quote_request.reload).to have_attributes(status: 'handled_manually', handled_manually_at: Time.current, handled_manually_by: user)
        expect(audits.sole).to have_attributes(subject: opportunity, actor: user, correlation_id: quote_request.correlation_id)
        expect(audits.sole.payload).to eq(
          'quote_request_id' => quote_request.id, 'previous_status' => 'awaiting_reply', 'from_stage' => 'qualificado',
          'to_stage' => 'proposta_enviada', 'mode' => 'single'
        )
      end
    end

    context 'when the request asks for a correction' do
      let(:quote_status) { :correction_requested }

      it 'accepts it and keeps the previous status in the audit' do
        handle

        expect(quote_request.reload).to be_handled_manually
        expect(audits.sole.payload['previous_status']).to eq('correction_requested')
      end
    end

    context 'when already in proposta_enviada' do
      let(:stage) { :proposta_enviada }

      it 'records no stage event' do
        handle

        expect(ScanSolo::PipelineStageEvent.where(opportunity: opportunity)).to be_none
        expect(quote_request.reload).to be_handled_manually
        expect(audits.sole.payload).to include('from_stage' => 'proposta_enviada', 'to_stage' => 'proposta_enviada')
      end
    end

    %w[single bulk].each do |mode|
      it "sends nothing in #{mode} mode (RF-17)" do
        expect { handle(mode: mode) }.to not_change(Message, :count)
          .and(not_change(ScanSolo::MakeRequest, :count))
          .and(not_change(ScanSolo::ProposalVersion, :count))
          .and(not_change { enqueued_jobs.count { |job| [SendReplyJob, ActionMailer::MailDeliveryJob].include?(job[:job]) } })
      end
    end
  end

  describe 'post-proposal cadence by mode (RF-17)' do
    it 'keeps the enrollment created by the transition active with future scheduled attempts in single mode' do
      acted_at = Time.current
      handle(mode: 'single')

      enrollment = post_proposal_enrollments.sole
      expect(enrollment).to be_active
      expect(enrollment.attempts.map(&:result)).to all(eq('scheduled'))
      expect(enrollment.attempts.map(&:scheduled_at)).to all(be > acted_at)
      expect(audits.sole.payload).not_to have_key('cadence_skipped')
    end

    it 'cancels the enrollment created by the transition in bulk mode' do
      handle(mode: 'bulk')

      enrollment = post_proposal_enrollments.sole
      expect(enrollment).to be_cancelled
      expect(enrollment.attempts.scheduled).to be_none
      expect(audits.sole.payload).to include('mode' => 'bulk', 'cadence_skipped' => 'legacy_bulk')
    end

    context 'when already in proposta_enviada with an active and a paused enrollment' do
      let(:stage) { :proposta_enviada }
      let!(:active_enrollment) { ScanSolo::Cadence::EnrollmentService.call(opportunity: opportunity, cadence_definition: post_proposal_definition) }
      let!(:paused_enrollment) do
        older = ScanSolo::CadenceDefinition.create!(stage: 'proposta_enviada', version: 2, offsets: [48], active: false)
        ScanSolo::Cadence::LifecycleService.pause!(ScanSolo::Cadence::EnrollmentService.call(opportunity: opportunity, cadence_definition: older))
      end

      it 'cancels both in bulk mode' do
        handle(mode: 'bulk')

        expect([active_enrollment.reload, paused_enrollment.reload]).to all(be_cancelled)
        expect(ScanSolo::CadenceAttempt.where(enrollment: [active_enrollment, paused_enrollment]).scheduled).to be_none
        expect(audits.sole.payload).to include('cadence_skipped' => 'legacy_bulk')
      end

      it 'keeps both in single mode' do
        handle(mode: 'single')

        expect(active_enrollment.reload).to be_active
        expect(paused_enrollment.reload).to be_paused
      end
    end

    it 'persists nothing when the cancellation fails (RF-17 e)' do
      allow(ScanSolo::Cadence::LifecycleService).to receive(:cancel!).and_call_original
      allow(ScanSolo::Cadence::LifecycleService).to receive(:cancel!)
        .with(having_attributes(cadence_definition: post_proposal_definition)).and_raise(ActiveRecord::RecordInvalid)

      expect { handle(mode: 'bulk') }.to raise_error(ActiveRecord::RecordInvalid)

      expect(opportunity.reload.stage).to eq('qualificado')
      expect(quote_request.reload).to have_attributes(status: 'awaiting_reply', handled_manually_at: nil, handled_manually_by_id: nil)
      expect(ScanSolo::PipelineStageEvent.where(opportunity: opportunity)).to be_none
      expect(post_proposal_enrollments).to be_none
      expect(audits).to be_none
    end
  end

  it 'applies 1 of 2 concurrent actions and refuses the other as quote_request_closed (RF-20)' do
    outcomes = Array.new(2) do
      target = ScanSolo::PipelineOpportunity.find(opportunity.id)
      Thread.new do
        handle(mode: 'bulk', target: target)
        :handled
      rescue CustomExceptions::ScanSolo::HandledManuallyRejected => e
        e.code
      end
    end.map(&:value)

    expect(outcomes).to contain_exactly(:handled, 'quote_request_closed')
    expect(audits.count).to eq(1)
    expect(ScanSolo::PipelineStageEvent.where(opportunity: opportunity).count).to be <= 1
  end
end
