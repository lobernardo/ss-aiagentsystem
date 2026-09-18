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
    it 'rejects a second opportunity for the same conversation' do
      opportunity
      duplicate = described_class.new(account: account, contact: contact, conversation: conversation)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:conversation_id]).to be_present
    end
  end

  describe '#record_customer_interaction!' do
    it 'updates last_customer_interaction_at' do
      timestamp = 1.hour.ago

      opportunity.record_customer_interaction!(at: timestamp)

      expect(opportunity.reload.last_customer_interaction_at).to be_within(1.second).of(timestamp)
    end
  end
end
