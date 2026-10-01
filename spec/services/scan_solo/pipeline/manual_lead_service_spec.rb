# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Pipeline::ManualLeadService do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:channel) { create(:channel_whatsapp, account: account, sync_templates: false) }
  let(:inbox) { channel.inbox }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:owner) { create(:user, account: account, role: :agent) }
  let(:phone_number) { '+5511987654321' }
  let(:email) { 'ana@example.com' }
  let(:params) do
    { account: account, actor: admin, name: 'Ana Souza', phone_number: phone_number, email: email, company: 'Solar Ltda',
      owner_id: owner.id, inbox: inbox }
  end
  let(:now) { ActiveSupport::TimeZone['America/Sao_Paulo'].local(2026, 1, 5, 10, 0, 0) }
  let(:counts) do
    -> { [Contact.count, Conversation.count, ScanSolo::PipelineOpportunity.count, Message.count] }
  end

  before do
    travel_to(now)
    stub_request(:post, 'https://waba.360dialog.io/v1/configs/webhook')
    ScanSolo::CadenceDefinition.create!(stage: 'novo_lead', version: 1, offsets: [2, 24, 48, 96])
    ScanSolo::AiAgentConfig.draft_for!(account).update!(name: 'Agente', enabled: true, allowed_inbox_ids: [inbox.id])
    ScanSolo::AiAgent::PublishService.new(account: account).call
  end

  def expect_rejection(code, opportunity_id = nil)
    counts_before = counts.call

    expect { described_class.call(**params) }.to raise_error(CustomExceptions::ScanSolo::ManualLeadRejected) { |error|
      expect(error).to have_attributes(code: code, opportunity_id: opportunity_id)
    }
    expect(counts.call).to eq(counts_before)
  end

  describe 'contact resolution (RF-04)' do
    it 'creates one contact with the company when neither phone nor e-mail exist' do
      result = nil

      expect { result = described_class.call(**params) }.to change(Contact, :count).by(1)

      expect(result.contact_created).to be(true)
      expect(result.opportunity.contact).to have_attributes(name: 'Ana Souza', phone_number: phone_number, email: email,
                                                            custom_attributes: { 'empresa' => 'Solar Ltda' })
    end

    it 'reuses the contact found by phone' do
      contact = create(:contact, account: account, phone_number: phone_number, email: nil)

      result = nil
      expect { result = described_class.call(**params) }.not_to change(Contact, :count)
      expect(result).to have_attributes(contact_created: false)
      expect(result.opportunity.contact).to eq(contact)
    end

    it 'reuses the contact found only by e-mail' do
      contact = create(:contact, account: account, phone_number: nil, email: 'ANA@example.com')

      result = nil
      expect { result = described_class.call(**params) }.not_to change(Contact, :count)
      expect(result.opportunity.contact).to eq(contact)
    end

    it 'creates a single contact for two concurrent registrations of the same phone' do
      outcomes = Array.new(2) do
        Thread.new do
          described_class.call(**params)
        rescue CustomExceptions::ScanSolo::ManualLeadRejected => e
          e.code
        end
      end.map(&:value)

      expect(Contact.where(phone_number: phone_number).count).to eq(1)
      expect(outcomes.grep(described_class::Result).size).to eq(1)
      expect(outcomes).to include('opportunity_exists')
    end

    it 'rejects with contact_conflict when phone and e-mail resolve to different contacts' do
      create(:contact, account: account, phone_number: phone_number, email: nil)
      create(:contact, account: account, phone_number: nil, email: email)

      expect_rejection('contact_conflict')
    end
  end

  describe 'rejections (RF-05, RF-09)' do
    let!(:contact) { create(:contact, account: account, phone_number: phone_number, email: nil) }

    it 'rejects an opted-out contact with contact_opted_out' do
      ScanSolo::ContactExtension.resolve_for(contact).update!(opted_out: true, opted_out_at: now)

      expect_rejection('contact_opted_out')
    end

    it 'rejects a contact with an open opportunity with opportunity_exists and its id' do
      conversation = create(:conversation, account: account, inbox: inbox, contact: contact)
      open_opportunity = ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation,
                                                               stage: :em_qualificacao)

      expect_rejection('opportunity_exists', open_opportunity.id)
    end

    it 'registers a contact whose only opportunity is perdido' do
      conversation = create(:conversation, account: account, inbox: inbox, contact: contact)
      ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :perdido)

      result = described_class.call(**params)

      expect(result.opportunity).to have_attributes(stage: 'novo_lead', lead_source: 'manual')
      expect(result.opportunity.conversation).not_to eq(conversation)
    end
  end

  describe 'conversation and opportunity (RF-06)' do
    it 'creates one conversation in the inbox assigned to the owner and one novo_lead manual opportunity, lead state and audit' do
      result = nil

      expect { result = described_class.call(**params) }.to change(Conversation, :count).by(1)

      opportunity = result.opportunity
      expect(opportunity).to have_attributes(stage: 'novo_lead', lead_source: 'manual', owner_id: owner.id, last_customer_interaction_at: nil)
      expect(opportunity.conversation).to have_attributes(inbox_id: inbox.id, assignee_id: owner.id, contact_id: opportunity.contact_id)
      expect(opportunity.conversation.contact_inbox.source_id).to eq('5511987654321')
      expect(ScanSolo::LeadState.where(opportunity_id: opportunity.id).sole).to be_em_andamento
      audit = ScanSolo::AuditEvent.where(event_type: 'pipeline.opportunity_created', subject: opportunity).sole
      expect(audit).to have_attributes(actor: admin)
      expect(audit.payload).to include('source' => 'manual', 'conversation_id' => opportunity.conversation_id, 'contact_created' => true)
    end

    it 'reuses the open conversation without opportunity of the contact in the inbox' do
      contact = create(:contact, account: account, phone_number: phone_number, email: nil)
      conversation = create(:conversation, account: account, inbox: inbox, contact: contact, status: :open)

      result = nil
      expect { result = described_class.call(**params) }.not_to change(Conversation, :count)
      expect(result.opportunity.conversation).to eq(conversation)
    end

    it 'rolls back contact and conversation when the opportunity creation fails' do
      allow(ScanSolo::PipelineOpportunity).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)

      expect { described_class.call(**params) }.to raise_error(ActiveRecord::RecordInvalid)
                                               .and(not_change(Contact, :count))
        .and(not_change(Conversation, :count))
    end
  end

  describe 'Novo Lead cadence (RF-10)' do
    it 'consumes step 1 as skipped without message and keeps steps 2-4 at T+24/48/96 h, sending nothing at T+2 h' do
      opportunity = described_class.call(**params).opportunity

      enrollment = opportunity.cadence_enrollments.active.sole
      expect(enrollment.cadence_definition.stage).to eq('novo_lead')
      attempts = enrollment.attempts.order(:step)
      expect(attempts.first).to have_attributes(result: 'skipped', message_id: nil, last_block_reason: 'manual_initial_template')
      expect(attempts.drop(1).map { |attempt| [attempt.result, attempt.scheduled_at] })
        .to eq([24, 48, 96].map { |hours| ['scheduled', now + hours.hours] })
      expect(enrollment).to have_attributes(current_step: 1, next_attempt_at: now + 24.hours)

      travel 2.hours
      expect { ScanSolo::CadenceDueAttemptJob.perform_now }.not_to change(Message, :count)
    end
  end
end
