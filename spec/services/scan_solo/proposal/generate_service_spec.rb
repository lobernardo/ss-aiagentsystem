# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Proposal::GenerateService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :em_qualificacao)
  end
  let(:writer) { ScanSolo::LeadState::Writer.new(lead_state: opportunity.lead_state) }
  let(:correlation_id) { SecureRandom.uuid }

  before do
    draft = ScanSolo::AiAgentConfig.draft_for!(account)
    draft.update!(name: 'Agente', enabled: true, required_qualification_fields: ['Área'])
    ScanSolo::AiAgent::PublishService.new(account: account).call
  end

  def call
    described_class.call(opportunity: opportunity, correlation_id: correlation_id)
  end

  describe 'required-field validation (RF-74; satisfied = confirmado no estado do lead)' do
    it 'rejects the request and creates no proposal record when a required field is missing' do
      expect { call }.to raise_error(ActiveRecord::RecordInvalid, /campos obrigatórios da proposta incompletos: Área\z/)
      expect(ScanSolo::Proposal.where(opportunity: opportunity)).to be_none
    end

    it 'proceeds when all required fields are confirmed in the lead state' do
      writer.apply_field!(key: 'area', value: '800 m²', status: 'confirmado', source_message_id: nil)

      expect { call }.to change(ScanSolo::ProposalVersion, :count).by(1)
    end

    it 'rejects a required field present only in the Contact' do
      contact.update!(custom_attributes: { 'area_total' => '800 m²' })

      expect { call }.to raise_error(ActiveRecord::RecordInvalid, /incompletos: Área\z/)
      expect(ScanSolo::ProposalVersion.count).to eq(0)
    end
  end

  describe 'proposal gate by qualification status (lead state RF-08)' do
    let(:config) { ScanSolo::AiAgentConfig.published_for(account) }

    it 'generates with concluida and area inferido, which stays in missing_fields' do
      writer.apply_field!(key: 'area', value: '800 m²', status: 'inferido', source_message_id: nil)
      writer.complete!(at: Time.current)

      expect { call }.to change(ScanSolo::ProposalVersion, :count).by(1)
      expect(ScanSolo::LeadState::Projection.call(opportunity: opportunity.reload, config: config).status[:missing_fields]).to include('area')
    end

    it 'blocks with concluida and area faltante' do
      writer.complete!(at: Time.current)

      expect { call }.to raise_error(ActiveRecord::RecordInvalid, /incompletos: Área\z/)
      expect(ScanSolo::ProposalVersion.count).to eq(0)
    end

    it 'blocks with em_andamento and area inferido' do
      writer.apply_field!(key: 'area', value: '800 m²', status: 'inferido', source_message_id: nil)

      expect { call }.to raise_error(ActiveRecord::RecordInvalid, /incompletos: Área\z/)
      expect(ScanSolo::ProposalVersion.count).to eq(0)
    end
  end

  describe 'generation request (RF-75)' do
    before { writer.apply_field!(key: 'area', value: '800 m²', status: 'confirmado', source_message_id: nil) }

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
    before { writer.apply_field!(key: 'area', value: '800 m²', status: 'confirmado', source_message_id: nil) }

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
