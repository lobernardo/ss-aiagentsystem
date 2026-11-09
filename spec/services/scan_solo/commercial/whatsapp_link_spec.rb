# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Commercial::WhatsappLink do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:contact) { create(:contact, account: account, name: 'Ana Contato') }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :proposta_enviada)
  end
  let(:config) { ScanSolo::AiAgentConfig.draft_for!(account).tap { |draft| draft.update!(commercial_whatsapp_number: '+5511999999999') } }
  let(:company_status) { 'confirmado' }

  before do
    opportunity.lead_state.update!(fields: {
                                     'nome' => { 'value' => 'Ana Souza', 'status' => 'confirmado' },
                                     'empresa' => { 'value' => 'Solar Ltda', 'status' => company_status },
                                     'tipo_servico' => { 'value' => 'Levantamento topográfico', 'status' => 'confirmado' }
                                   })
  end

  def decoded_text(url)
    URI.decode_www_form_component(URI.parse(url).query.delete_prefix('text='))
  end

  it 'exposes the placeholder the model writes instead of the link' do
    expect(described_class::PLACEHOLDER).to eq('{{LINK_ARTUR}}')
  end

  it 'builds the wa.me link with Artur, the lead data and the proposal number (CT-05)' do
    version = ScanSolo::Proposal.create!(opportunity: opportunity).versions.create!(generate_correlation_id: SecureRandom.uuid)
    version.update!(proposal_number: 'SS-2026-000123')

    url = described_class.build(config: config, opportunity: opportunity.reload)

    expect(url).to start_with('https://wa.me/5511999999999?text=')
    expect(url).not_to include(' ', '+')
    expect(decoded_text(url)).to include('Artur', 'Ana Souza', 'Solar Ltda', 'Levantamento topográfico', 'SS-2026-000123')
  end

  it 'has no proposal reference without a proposal' do
    text = decoded_text(described_class.build(config: config, opportunity: opportunity))

    expect(text).not_to include('SS-', I18n.t('scan_solo.commercial.whatsapp_text.proposal', value: '').strip)
  end

  context 'when the company is nao_informado' do
    let(:company_status) { 'nao_informado' }

    it 'has no company line' do
      text = decoded_text(described_class.build(config: config, opportunity: opportunity))

      expect(text).not_to include('Solar Ltda', I18n.t('scan_solo.commercial.whatsapp_text.company', value: '').strip)
    end
  end

  it 'returns nil without the published number' do
    config.update!(commercial_whatsapp_number: nil)

    expect(described_class.build(config: config, opportunity: opportunity)).to be_nil
  end
end
