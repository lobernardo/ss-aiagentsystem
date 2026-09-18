# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Pipeline::OpportunityQuery do
  let(:account) { create(:account) }
  let(:owner) { create(:user, account: account) }
  let(:other_owner) { create(:user, account: account) }

  def build_opportunity(stage: :novo_lead, owner: nil, last_customer_interaction_at: nil)
    contact = create(:contact, account: account)
    conversation = create(:conversation, account: account, contact: contact)
    ScanSolo::PipelineOpportunity.create!(
      account: account,
      contact: contact,
      conversation: conversation,
      stage: stage,
      owner: owner,
      last_customer_interaction_at: last_customer_interaction_at
    )
  end

  describe '.stale?' do
    it 'flags an opportunity exactly 48 hours since the last customer interaction' do
      opportunity = build_opportunity(last_customer_interaction_at: 48.hours.ago)

      expect(described_class.stale?(opportunity)).to be(true)
    end

    it 'does not flag an opportunity one second under 48 hours' do
      opportunity = build_opportunity(last_customer_interaction_at: 48.hours.ago + 1.second)

      expect(described_class.stale?(opportunity)).to be(false)
    end

    it 'does not flag an opportunity with no recorded interaction' do
      opportunity = build_opportunity(last_customer_interaction_at: nil)

      expect(described_class.stale?(opportunity)).to be(false)
    end
  end

  describe '#results filters' do
    it 'narrows by stage' do
      matching = build_opportunity(stage: :em_contato)
      build_opportunity(stage: :novo_lead)

      results = described_class.new(scope: ScanSolo::PipelineOpportunity.where(account: account), stage: 'em_contato').results

      expect(results).to contain_exactly(matching)
    end

    it 'narrows by owner' do
      matching = build_opportunity(owner: owner)
      build_opportunity(owner: other_owner)

      results = described_class.new(scope: ScanSolo::PipelineOpportunity.where(account: account), owner_id: owner.id).results

      expect(results).to contain_exactly(matching)
    end

    it 'narrows by stale state' do
      stale_opportunity = build_opportunity(last_customer_interaction_at: 49.hours.ago)
      fresh_opportunity = build_opportunity(last_customer_interaction_at: 1.hour.ago)

      stale_results = described_class.new(scope: ScanSolo::PipelineOpportunity.where(account: account), stale: true).results
      fresh_results = described_class.new(scope: ScanSolo::PipelineOpportunity.where(account: account), stale: false).results

      expect(stale_results).to contain_exactly(stale_opportunity)
      expect(fresh_results).to contain_exactly(fresh_opportunity)
    end
  end
end
