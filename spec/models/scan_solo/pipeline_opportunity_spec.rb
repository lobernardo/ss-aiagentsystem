# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::PipelineOpportunity do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }

  let(:opportunity) do
    described_class.create!(account: account, contact: contact, conversation: conversation, stage: :novo_lead)
  end

  describe 'stage vocabulary' do
    it 'restricts stage to the eight defined values in order' do
      expect(described_class.stages.keys).to eq(
        %w[novo_lead em_contato em_qualificacao qualificado proposta_enviada negociacao ganho perdido]
      )
    end

    it 'raises when persisting an out-of-vocabulary stage' do
      expect { opportunity.update!(stage: 'inventado') }.to raise_error(ArgumentError)
      expect(opportunity.reload.stage).to eq('novo_lead')
    end
  end

  describe 'stage independence from labels/custom attributes' do
    it 'leaves the stage column unchanged when only conversation labels/custom attributes change' do
      opportunity

      expect do
        conversation.update!(custom_attributes: { priority: 'high' })
        conversation.update!(label_list: ['vip'])
      end.not_to(change { opportunity.reload.stage })
    end
  end

  describe 'uniqueness' do
    it 'rejects a second opportunity for the same conversation through the unique index' do
      opportunity
      duplicate = described_class.new(account: account, contact: contact, conversation: conversation)

      expect { duplicate.save! }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe '#record_customer_interaction!' do
    it 'updates last_customer_interaction_at' do
      timestamp = 1.hour.ago

      opportunity.record_customer_interaction!(at: timestamp)

      expect(opportunity.reload.last_customer_interaction_at).to be_within(1.second).of(timestamp)
    end
  end

  describe 'lead_source (RF-01)' do
    it 'accepts nil, website and manual' do
      [nil, 'website', 'manual'].each do |source|
        expect(described_class.new(account: account, contact: contact, conversation: conversation, lead_source: source)).to be_valid
      end
    end

    it 'rejects a value outside the vocabulary' do
      record = described_class.new(account: account, contact: contact, conversation: conversation, lead_source: 'site')

      expect(record).not_to be_valid
      expect(record.errors[:lead_source]).to be_present
    end
  end

  describe '#conversation_extension' do
    it 'resolves through the shared conversation id' do
      extension = ScanSolo::ConversationExtension.create!(conversation: conversation, ai_control_state: :awaiting_human)

      expect(described_class.find(opportunity.id).conversation_extension).to eq(extension)
    end
  end

  describe '#quote_request' do
    it 'returns the opportunity request' do
      quote_request = ScanSolo::QuoteRequest.create!(account: account, opportunity: opportunity, correlation_id: SecureRandom.uuid)

      expect(opportunity.reload.quote_request).to eq(quote_request)
    end
  end

  describe '#lead_email_valid? (RF-08)' do
    it 'is false without an email' do
      contact.update!(email: nil)

      expect(opportunity.lead_email_valid?).to be false
    end

    it 'is false for a malformed email' do
      contact.update_column(:email, 'x@') # rubocop:disable Rails/SkipsModelValidations

      expect(opportunity.lead_email_valid?).to be false
    end

    it 'is true for a valid email' do
      contact.update!(email: 'lead@example.com')

      expect(opportunity.lead_email_valid?).to be true
    end
  end
end
