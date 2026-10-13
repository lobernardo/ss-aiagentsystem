# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Quote::RequestEmail::Snapshot do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) do
    create(:contact, account: account, name: 'Ana Souza', email: 'ana@amaggi.com.br', phone_number: '+5565999990000',
                     custom_attributes: { 'empresa' => 'Empresa do Contato', 'cnpj' => '11.111.111/0001-11', 'telefone' => '+5511888880000' })
  end
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:opportunity) { ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :qualificado) }
  let(:lead_state) { opportunity.lead_state }
  let(:writer) { ScanSolo::LeadState::Writer.new(lead_state: lead_state) }
  let(:config) { ScanSolo::AiAgentConfig.draft_for!(account) }
  let(:source_message) { create(:message, account: account, conversation: conversation, message_type: :incoming, created_at: 10.minutes.ago) }
  let(:snapshot) { described_class.call(opportunity: ScanSolo::PipelineOpportunity.find(opportunity.id), config: config) }

  def attach(message, file_type, name, content_type, bytes = 'conteudo')
    attachment = message.attachments.new(account_id: account.id, file_type: file_type)
    attachment.file.attach(io: StringIO.new(bytes), filename: name, content_type: content_type)
    attachment.save!
    attachment
  end

  describe 'field precedence (CT-02)' do
    it 'prefers a non-faltante lead state value over the contact and falls back to the contact otherwise' do
      writer.apply_field!(key: 'empresa', value: 'AMAGGI Exportação e Importação Ltda.', status: 'confirmado', source_message_id: source_message.id)
      lead_state.update!(fields: lead_state.fields.merge('cnpj' => { 'value' => '99.999.999/0001-99', 'status' => 'faltante' }))

      expect(snapshot['fields']['empresa']).to eq('value' => 'AMAGGI Exportação e Importação Ltda.', 'inferred' => false)
      expect(snapshot['fields']['cnpj']).to eq('value' => '11.111.111/0001-11', 'inferred' => false)
      expect(snapshot['fields']['area']).to eq('value' => nil, 'inferred' => false)
    end

    it 'marks inferido values' do
      writer.apply_field!(key: 'profundidade', value: '3 m', status: 'inferido', source_message_id: source_message.id)

      expect(snapshot['fields']['profundidade']).to eq('value' => '3 m', 'inferred' => true)
    end

    it 'lists the CT-02 keys in a fixed order, without telefone' do
      expect(snapshot.keys).to eq(%w[fields contact_name phone missing_labels validation_mode conversation_url location_sources attachments])
      expect(snapshot['fields'].keys).to eq(described_class::FIELD_KEYS)
      expect(snapshot['fields']).not_to have_key('telefone')
      expect(described_class::OTHER_KEYS.size).to eq(16)
    end

    it 'reads the contact name, the config missing labels, the validation mode and the conversation url' do
      config.update!(quote_email_validation_mode: false)

      expect(snapshot).to include(
        'contact_name' => 'Ana Souza',
        'missing_labels' => ScanSolo::Qualification::FieldResolver.call(opportunity: opportunity, config: config).missing_labels,
        'validation_mode' => false,
        'conversation_url' => ScanSolo::Quote::EmailComposer.conversation_url(account.id, conversation.display_id)
      )
    end
  end

  describe 'phone (RF-07)' do
    it 'ignores the lead state telefone and uses only the contact phone_number' do
      writer.apply_field!(key: 'telefone', value: '+5521777770000', status: 'confirmado', source_message_id: source_message.id)

      expect(snapshot['phone']).to eq('+5565999990000')
      expect(snapshot.to_json).not_to include('+5521777770000')
    end

    it 'is nil without a contact phone_number' do
      contact.update!(phone_number: nil)

      expect(snapshot['phone']).to be_nil
    end
  end

  describe 'attachments and locations (RF-10, RF-13)' do
    let(:first) do
      create(:message, account: account, conversation: conversation, message_type: :incoming, created_at: 5.minutes.ago,
                       content: 'Local: https://www.google.com/maps?q=-13.0053596,-55.9400673 e https://example.com/x')
    end
    let(:second) { create(:message, account: account, conversation: conversation, message_type: :incoming, created_at: 3.minutes.ago) }
    let(:outgoing) do
      create(:message, account: account, conversation: conversation, message_type: :outgoing, created_at: 2.minutes.ago,
                       content: 'https://www.google.com/maps?q=1,1')
    end
    let(:other) do
      create(:message, account: account, conversation: create(:conversation, account: account, inbox: inbox, contact: contact),
                       message_type: :incoming, created_at: 4.minutes.ago, content: 'https://www.google.com/maps?q=2,2')
    end

    before do
      attach(second, :file, 'planta-executiva.pdf', 'application/pdf', 'x' * 2048)
      second.attachments.create!(account_id: account.id, file_type: :location, coordinates_lat: -13.00536, coordinates_long: -55.94007)
      attach(first, :image, 'foto.png', 'image/png')
      attach(outgoing, :file, 'proposta.pdf', 'application/pdf')
      attach(other, :image, 'outra.png', 'image/png')
      writer.apply_field!(key: 'link_local', value: 'https://maps.app.goo.gl/abc', status: 'inferido', source_message_id: second.id)
    end

    it 'lists the incoming attachments of the opportunity conversation in order of receipt' do
      expect(snapshot['attachments']).to eq(
        [
          { 'id' => first.attachments.sole.id, 'name' => 'foto.png', 'type' => 'PNG', 'file_type' => 'image', 'byte_size' => 8 },
          { 'id' => second.attachments.file.sole.id, 'name' => 'planta-executiva.pdf', 'type' => 'PDF', 'file_type' => 'file',
            'byte_size' => 2048 }
        ]
      )
    end

    it 'uses the file_type as type when the name has no extension' do
      attach(second, :audio, 'gravacao', 'audio/ogg')

      expect(snapshot['attachments'].last).to include('name' => 'gravacao', 'type' => 'audio', 'file_type' => 'audio')
    end

    it 'lists map URLs, location attachments and the lead state link in order of receipt' do
      expect(snapshot['location_sources']).to eq(
        [
          'https://www.google.com/maps?q=-13.0053596,-55.9400673',
          'https://www.google.com/maps?q=-13.00536,-55.94007',
          'https://maps.app.goo.gl/abc'
        ]
      )
    end
  end

  describe 'determinism and read only (RF-01, RNF-01)' do
    before do
      writer.apply_field!(key: 'empresa', value: 'AMAGGI', status: 'confirmado', source_message_id: source_message.id)
      attach(source_message, :file, 'planta.pdf', 'application/pdf')
      source_message.attachments.create!(account_id: account.id, file_type: :location, coordinates_lat: -13.0, coordinates_long: -55.9)
    end

    it 'returns the same hash and JSON for the same state' do
      other_call = described_class.call(opportunity: ScanSolo::PipelineOpportunity.find(opportunity.id), config: config)

      expect(other_call).to eq(snapshot)
      expect(other_call.to_json).to eq(snapshot.to_json)
      expect(JSON.parse(snapshot.to_json)).to eq(snapshot)
    end

    it 'writes nothing and makes no HTTP request' do
      opportunity
      WebMock.reset!

      expect { snapshot }.to not_change(Message, :count)
        .and(not_change(ScanSolo::AuditEvent, :count))
        .and(not_change(ScanSolo::LeadStateEvent, :count))
        .and(not_change { lead_state.reload.updated_at })
      expect(a_request(:any, /.*/)).not_to have_been_made
    end
  end

  describe 'nao_informado (proposta-template-local RF-31 d)' do
    before { config.update!(required_qualification_fields: ['Profundidade de investigação']) }

    it 'keeps the status without the lead words or the contact value and lists the label' do
      contact.update!(custom_attributes: contact.custom_attributes.merge('profundidade' => '9 m', 'condicoes_especiais' => 'NF'))
      writer.apply_field!(key: 'profundidade', value: 'não sei', status: 'nao_informado', source_message_id: source_message.id)
      writer.apply_field!(key: 'condicoes_especiais', value: 'não tenho', status: 'nao_informado', source_message_id: source_message.id)

      expect(snapshot['fields']['profundidade']).to eq('value' => nil, 'inferred' => false, 'not_informed' => true)
      expect(snapshot['not_informed']).to eq(
        [{ 'key' => 'profundidade', 'label' => 'Profundidade de investigação' }, { 'key' => 'condicoes_especiais', 'label' => 'Condições especiais' }]
      )
      expect(snapshot.to_json).not_to include('não sei', 'não tenho', '9 m')
    end

    it 'has no not_informed key without a nao_informado field' do
      writer.apply_field!(key: 'profundidade', value: '3 m', status: 'confirmado', source_message_id: source_message.id)

      expect(snapshot).not_to have_key('not_informed')
      expect(snapshot['fields'].values).to all(satisfy { |field| field.keys == %w[value inferred] })
    end
  end
end
