# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Pipeline::OpportunityQuery do
  let(:account) { create(:account) }
  let(:owner) { create(:user, account: account) }
  let(:other_owner) { create(:user, account: account) }

  let(:now) { Time.zone.parse('2026-11-08T12:00:00Z') }

  def build_opportunity(stage: :novo_lead, owner: nil, last_customer_interaction_at: nil, created_at: Time.current)
    contact = create(:contact, account: account)
    conversation = create(:conversation, account: account, contact: contact)
    ScanSolo::PipelineOpportunity.create!(
      account: account,
      contact: contact,
      conversation: conversation,
      stage: stage,
      owner: owner,
      last_customer_interaction_at: last_customer_interaction_at,
      created_at: created_at
    )
  end

  describe 'stalled rule (Relatórios RF-04)' do
    let(:cases) do
      {
        interaction_47h59: [build_opportunity(last_customer_interaction_at: now - 47.hours - 59.minutes, created_at: now - 10.days), false],
        interaction_48h: [build_opportunity(last_customer_interaction_at: now - 48.hours, created_at: now - 10.days), true],
        nil_created_48h: [build_opportunity(created_at: now - 48.hours), true],
        nil_created_47h59: [build_opportunity(created_at: now - 47.hours - 59.minutes), false],
        ganho_30d: [build_opportunity(stage: :ganho, last_customer_interaction_at: now - 30.days, created_at: now - 30.days), false],
        perdido_30d: [build_opportunity(stage: :perdido, last_customer_interaction_at: now - 30.days, created_at: now - 30.days), false]
      }
    end

    it 'applies the 48 h threshold to the last interaction, falling back to created_at, never to terminal stages' do
      cases.each do |name, (opportunity, expected)|
        expect(described_class.stale?(opportunity, now: now)).to be(expected), "#{name} expected #{expected}"
      end
    end

    it 'returns from stalled_scope exactly the opportunities stale? flags' do
      scope = ScanSolo::PipelineOpportunity.where(account: account)
      expected = cases.values.select { |(_, stale)| stale }.map(&:first)

      expect(described_class.stalled_scope(scope, as_of: now)).to match_array(expected)
      expect(scope.select { |opportunity| described_class.stale?(opportunity, now: now) }).to match_array(expected)
    end

    it 'defaults now to the current time' do
      opportunity = build_opportunity(last_customer_interaction_at: 48.hours.ago)

      expect(described_class.stale?(opportunity)).to be(true)
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

    it 'narrows by stale state with the stalled rule' do
      stale_opportunity = build_opportunity(last_customer_interaction_at: 49.hours.ago)
      stale_without_interaction = build_opportunity(created_at: 49.hours.ago)
      fresh_opportunity = build_opportunity(last_customer_interaction_at: 1.hour.ago, created_at: 10.days.ago)
      won_opportunity = build_opportunity(stage: :ganho, last_customer_interaction_at: 30.days.ago)

      stale_results = described_class.new(scope: ScanSolo::PipelineOpportunity.where(account: account), stale: true).results
      fresh_results = described_class.new(scope: ScanSolo::PipelineOpportunity.where(account: account), stale: false).results

      expect(stale_results).to contain_exactly(stale_opportunity, stale_without_interaction)
      expect(fresh_results).to contain_exactly(fresh_opportunity, won_opportunity)
    end
  end
end
