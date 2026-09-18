# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Proposal::GenerateService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, custom_attributes: { 'budget' => '5000' }) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :em_qualificacao)
  end
  let(:correlation_id) { SecureRandom.uuid }

  before do
    draft = ScanSolo::AiAgentConfig.draft_for!(account)
    draft.update!(name: 'Agente', enabled: true, required_qualification_fields: %w[budget])
    ScanSolo::AiAgent::PublishService.new(account: account).call
  end

  def call
    described_class.call(opportunity: opportunity, correlation_id: correlation_id)
  end

  describe 'required-field validation (RF-74)' do
    it 'rejects the request and creates no proposal record when a required field is missing' do
      contact.update!(custom_attributes: {})

      expect { call }.to raise_error(ActiveRecord::RecordInvalid)
      expect(ScanSolo::Proposal.where(opportunity: opportunity)).to be_none
    end

    it 'proceeds when all required fields are present' do
      expect { call }.not_to raise_error
    end
  end

  describe 'generation request (RF-75)' do
    it 'creates a proposal version and persists commercial fields only after the mock callback is validated' do
      version = call

      expect(version).to be_persisted
      expect(version).to be_generated
      expect(version.value).to eq(ScanSolo::Proposal::MockProvider::DEFAULT_VALUE)
      expect(version.currency).to eq(ScanSolo::Proposal::MockProvider::DEFAULT_CURRENCY)
      expect(version.artifact_url).to be_present
    end

    it 'does not persist commercial fields from the request alone, only from the provider callback' do
      no_op_provider = Class.new do
        def self.request_generation(**)
          nil
        end
      end

      version = described_class.call(opportunity: opportunity, correlation_id: correlation_id, provider: no_op_provider)

      expect(version).to be_generating
      expect(version.value).to be_nil
      expect(version.currency).to be_nil
    end
  end

  describe 'RF-73: proposal.generate alone sends nothing' do
    it 'creates zero outbound messages' do
      expect { call }.not_to(change { conversation.messages.outgoing.count })
    end
  end

  describe 'RF-76: the model never writes value/discount/total directly' do
    it 'exposes no way for a caller to pass a commercial value into GenerateService' do
      accepted_keywords = described_class.method(:call).parameters.select { |type, _| type == :key || type == :keyreq }.map(&:last)

      expect(accepted_keywords).not_to include(:value, :currency, :price, :discount, :total)
    end
  end
end
