require 'rails_helper'

RSpec.describe ScanSolo::AiTurn::AttachmentReader do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:content) { nil }
  let(:message) { create(:message, account: account, conversation: conversation, message_type: :incoming, content: content) }
  let(:result) { described_class.call(message: message.reload) }

  def attach_pdf(name)
    attachment = message.attachments.new(account_id: account.id, file_type: :file)
    attachment.file.attach(io: Rails.root.join("spec/fixtures/files/scansolo/#{name}").open, filename: name, content_type: 'application/pdf')
    attachment.save!
    attachment
  end

  it 'builds link_local from the coordinates of a location without external_url (RF-18)' do
    attachment = message.attachments.create!(account_id: account.id, file_type: :location, coordinates_lat: -22.9, coordinates_long: -43.2)

    expect(result.updates).to eq([{ key: 'link_local', value: 'https://www.google.com/maps?q=-22.9,-43.2', source_attachment_id: attachment.id }])
    expect(result.evidence).to eq([{ attachment_id: attachment.id, file_type: 'location', file_name: nil, extracted: true, reason: nil }])
  end

  it 'prefers the external_url of a location' do
    attachment = message.attachments.create!(account_id: account.id, file_type: :location, coordinates_lat: -22.9, coordinates_long: -43.2,
                                             external_url: 'https://maps.example.com/p/1')

    expect(result.updates).to eq([{ key: 'link_local', value: 'https://maps.example.com/p/1', source_attachment_id: attachment.id }])
  end

  it 'extracts cnpj, empresa and endereco_obra from a PDF (RF-19)' do
    attachment = attach_pdf('lead_state_company.pdf')

    expect(result.updates).to eq(
      [
        { key: 'cnpj', value: '12.345.678/0001-90', source_attachment_id: attachment.id },
        { key: 'empresa', value: 'ACME Engenharia Ltda', source_attachment_id: attachment.id },
        { key: 'endereco_obra', value: 'Rua das Laranjeiras, 100 - Rio de Janeiro/RJ', source_attachment_id: attachment.id }
      ]
    )
    expect(result.evidence).to eq([{ attachment_id: attachment.id, file_type: 'file', file_name: 'lead_state_company.pdf',
                                     extracted: true, reason: nil }])
  end

  it 'reports a scanned PDF without text (RF-20)' do
    attach_pdf('lead_state_scanned.pdf')

    expect(result.updates).to be_empty
    expect(result.evidence.sole).to include(extracted: false, reason: 'no_extractable_text')
  end

  it 'skips a PDF with more than 10 pages' do
    attach_pdf('lead_state_11_pages.pdf')

    expect(result.updates).to be_empty
    expect(result.evidence.sole).to include(extracted: false, reason: 'too_many_pages')
  end

  it 'skips a PDF above 10 MB before opening it' do
    attachment = attach_pdf('lead_state_company.pdf')
    attachment.file.blob.update_column(:byte_size, 10.megabytes + 1) # rubocop:disable Rails/SkipsModelValidations

    expect(PDF::Reader).not_to receive(:new)
    expect(result.updates).to be_empty
    expect(result.evidence.sole).to include(extracted: false, reason: 'too_large')
  end

  it 'reports a corrupt PDF as an extraction error' do
    attach_pdf('lead_state_corrupt.pdf')

    expect(result.updates).to be_empty
    expect(result.evidence.sole).to include(file_name: 'lead_state_corrupt.pdf', extracted: false,
                                            reason: 'extraction_error: PDF::Reader::MalformedPDFError')
  end

  it 'reports an unsupported attachment type' do
    attachment = message.attachments.new(account_id: account.id, file_type: :image)
    attachment.file.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'avatar.png', content_type: 'image/png')
    attachment.save!

    expect(result.updates).to be_empty
    expect(result.evidence).to eq([{ attachment_id: attachment.id, file_type: 'image', file_name: 'avatar.png', extracted: false,
                                     reason: 'unsupported_type' }])
  end

  context 'with a map URL in the text (RF-18a)' do
    let(:content) { 'segue o local https://maps.app.goo.gl/abc' }

    it 'fills link_local without an attachment origin' do
      expect(result.updates).to eq([{ key: 'link_local', value: 'https://maps.app.goo.gl/abc', source_attachment_id: nil }])
      expect(result.urls).to eq(['https://maps.app.goo.gl/abc'])
      expect(result.evidence).to be_empty
    end
  end

  context 'with other map hosts' do
    let(:content) do
      'links: https://www.google.com/maps/place/x, https://maps.google.com.br/?q=1 e https://goo.gl/maps/xyz. ' \
        'Não: https://google.com/search?q=maps'
    end

    it 'recognizes only map URLs' do
      expect(result.updates.pluck(:value)).to eq(['https://www.google.com/maps/place/x', 'https://maps.google.com.br/?q=1', 'https://goo.gl/maps/xyz'])
      expect(result.urls.size).to eq(4)
    end
  end

  context 'with a non-map URL' do
    let(:content) { 'o edital está em https://exemplo.com.br/edital' }

    it 'fills no field and returns the URL' do
      expect(result.updates).to be_empty
      expect(result.urls).to eq(['https://exemplo.com.br/edital'])
    end
  end

  context 'without network or model access (RNF-02)' do
    let(:content) { 'segue o local https://maps.app.goo.gl/abc e o edital https://exemplo.com.br/edital' }

    it 'makes no HTTP request and no LLM call' do
      message.attachments.create!(account_id: account.id, file_type: :location, coordinates_lat: -22.9, coordinates_long: -43.2)
      attach_pdf('lead_state_company.pdf')
      allow(ScanSolo::TestMode::MockLlmProvider).to receive(:call).and_raise('LLM called')
      allow(RubyLLM).to receive(:chat).and_raise('LLM called')

      first = described_class.call(message: message.reload)
      second = described_class.call(message: message.reload)

      expect(first.to_h).to eq(second.to_h)
      expect(first.updates.size).to eq(5)
      expect(a_request(:any, //)).not_to have_been_made
    end
  end
end
