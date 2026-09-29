require 'rails_helper'

RSpec.describe ScanSolo::LeadState::Projection do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, name: '', email: nil, phone_number: nil, custom_attributes: {}) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:opportunity) { ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :em_qualificacao) }
  let(:lead_state) { opportunity.lead_state }
  let(:writer) { ScanSolo::LeadState::Writer.new(lead_state: lead_state) }
  let(:config) { ScanSolo::AiAgentConfig.new(required_qualification_fields: ['Área']) }
  let(:message) { create(:message, account: account, conversation: conversation, message_type: :incoming) }
  let(:pending_updates) { [] }
  let(:projection) { described_class.call(opportunity: opportunity.reload, config: config, pending_updates: pending_updates) }

  it 'offers only faltante keys, required before complementary, in RF-02 order (RF-09)' do
    (ScanSolo::Qualification::FieldResolver::CATALOG_KEYS - %w[area cnpj empresa]).each do |key|
      writer.apply_field!(key: key, value: "valor #{key}", status: 'confirmado', source_message_id: message.id)
    end

    expect(projection.eligible_keys).to eq(%w[area empresa cnpj])
  end

  it 'never offers confirmado or inferido keys' do
    writer.apply_field!(key: 'area', value: '800 m²', status: 'confirmado', source_message_id: message.id)
    writer.apply_field!(key: 'cnpj', value: '12.345.678/0001-90', status: 'inferido', source_message_id: message.id)

    expect(projection.eligible_keys).not_to include('area', 'cnpj')
    expect(projection.eligible_keys.first).to eq('nome')
  end

  it 'lists a required inferido key as missing and not as confirmed (RF-03, RF-04)' do
    writer.apply_field!(key: 'area', value: '800 m²', status: 'inferido', source_message_id: message.id)
    writer.apply_field!(key: 'bairro', value: 'Centro', status: 'confirmado', source_message_id: message.id)

    expect(projection.status).to include(stage: 'em_qualificacao', missing_fields: ['area'], confirmed_fields: ['bairro'])
  end

  it 'derives the owner from the opportunity without writing to the lead state (RF-03)' do
    agent = create(:user, account: account, role: :agent)
    described_class.call(opportunity: opportunity.reload, config: config)

    expect { opportunity.update!(owner: agent) }.not_to(change { [lead_state.reload.updated_at, lead_state.events.count] })
    expect(projection.status[:owner_id]).to eq(agent.id)
  end

  it 'offers no key once the qualification is concluida (RF-22)' do
    writer.complete!(at: Time.current)

    expect(projection.eligible_keys).to eq([])
    expect(projection.qualification).to include(status: 'concluida')
  end

  context 'with a pending link_local extraction of the current message (RF-17)' do
    let(:pending_updates) { [{ key: 'link_local', value: 'https://maps.app.goo.gl/abc', source_attachment_id: nil }] }

    it 'shows it as inferido and leaves it out of the eligible keys' do
      field = projection.blocks['local'].find { |candidate| candidate[:key] == 'link_local' }

      expect(field).to include(value: 'https://maps.app.goo.gl/abc', status: 'inferido')
      expect(projection.eligible_keys).not_to include('link_local')
      expect(lead_state.reload.fields['link_local']['status']).to eq('faltante')
    end

    it 'never overlays a confirmado value (RF-07)' do
      writer.apply_field!(key: 'link_local', value: 'https://maps.google.com/?q=1,2', status: 'confirmado', source_message_id: message.id)

      field = projection.blocks['local'].find { |candidate| candidate[:key] == 'link_local' }
      expect(field).to include(value: 'https://maps.google.com/?q=1,2', status: 'confirmado')
    end
  end

  it 'keeps every classification when the intent changes (RF-15)' do
    classifications = -> { described_class.call(opportunity: opportunity.reload, config: config).blocks.values.flatten.pluck(:key, :classification) }
    before_change = classifications.call

    writer.set_intent!(intent: 'envio_documentos', source_message_id: message.id)

    expect(classifications.call).to eq(before_change)
    expect(before_change.select { |_key, classification| classification == 'obrigatorio' }).to eq([%w[area obrigatorio]])
  end

  it 'projects the CT-01 shape: 6 blocks in RF-02 order, next action, authorizations and history' do
    writer.set_intent!(intent: 'orcamento', source_message_id: message.id)
    writer.record_next_action!(value: 'proposta', source_message_id: message.id)
    writer.authorize_action!(action: 'proposta', source_message_id: message.id)

    expect(projection.blocks.keys).to eq(%w[identificacao servico local escopo execucao comercial])
    expect(projection.blocks.values.sum(&:size)).to eq(34)
    expect(projection.blocks['identificacao'].first.keys)
      .to eq(%i[key label value status classification updated_at source_message_id source_attachment_id])
    expect(projection).to have_attributes(intent: 'orcamento', next_action: include(value: 'proposta', source_message_id: message.id))
    expect(projection.authorized_actions).to contain_exactly(include(action: 'proposta', source_message_id: message.id))
    expect(projection.history.pluck(:subject)).to eq(%w[intent next_action])
    expect(projection.status[:next_action]).to eq('proposta')
  end

  it 'is deterministic for the same state and config (RNF-02)' do
    writer.apply_field!(key: 'area', value: '800 m²', status: 'inferido', source_message_id: message.id)

    expect(described_class.call(opportunity: opportunity.reload, config: config).to_h).to eq(projection.to_h)
  end
end
