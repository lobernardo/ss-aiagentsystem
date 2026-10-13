# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Proposal::TemplateRenderer do
  let(:values) do
    ScanSolo::Proposal::TemplateDocument::PLACEHOLDERS.index_with { |name| "valor #{name.downcase}" }
                                                      .merge('DESCRICAO_ESCOPO' => "Item A <b>&</b>\nItem B")
  end
  let(:template_bytes) { scan_solo_docx_valid }
  let(:rendered) { described_class.call(template_bytes: template_bytes, values: values) }
  let(:document_xml) { Zip::File.open_buffer(rendered).read('word/document.xml').force_encoding('UTF-8') }
  let(:word) { ScanSolo::Proposal::TemplateDocument::NAMESPACES }

  it 'escapes the value as text and turns its line break into a w:br in the same run (RF-06 a, c)' do
    expect(document_xml).to include('Item A &lt;b&gt;&amp;&lt;/b&gt;')
    expect(document_xml).not_to include('<b>')

    document = Nokogiri::XML(document_xml, &:strict)
    expect(document.errors).to be_empty
    scope_run = document.at_xpath('//w:r[w:br]', word)
    expect(scope_run.xpath('w:br', word).size).to eq(1)
    expect(scope_run.xpath('w:t', word).map(&:text)).to eq(['Campo sintético: Item A <b>&</b>', 'Item B.'])
    expect(scope_run.xpath('w:t', word).pluck('xml:space')).to all(eq('preserve'))
    expect(document.xpath('//w:br', word).size).to eq(1)
  end

  it 'replaces the 16 placeholders, header included, and leaves no {{NAME}}' do
    zip = Zip::File.open_buffer(rendered)

    expect(zip.read('word/header1.xml').force_encoding('UTF-8')).to include('Proposta valor numero_proposta')
    expect(document_xml).to include('valor valor_extenso', 'valor trecho_profundidade')
    expect(document_xml).not_to match(/\{\{[A-Z_]+\}\}/)
  end

  it 'removes control characters except the line break (RF-06 b)' do
    values['NOME_EMPRESA'] = "Empresa\u0007 Sintética\u0000\tLtda"

    expect(document_xml).to include('Empresa SintéticaLtda')
    expect(document_xml).not_to include("\u0007")
  end

  it 'keeps the run formatting of the placeholder (RF-06 d)' do
    bytes = scan_solo_docx(paragraphs: ['Escopo: {{DESCRICAO_ESCOPO}}'], bold: ['DESCRICAO_ESCOPO'])
    document = Nokogiri::XML(Zip::File.open_buffer(described_class.call(template_bytes: bytes, values: values)).read('word/document.xml'))

    run = document.at_xpath('//w:r[w:br]', word)
    expect(run.at_xpath('w:rPr/w:b', word)).to be_present
    expect(run.xpath('w:t', word).map(&:text)).to eq(['Escopo: Item A <b>&</b>', 'Item B'])
  end

  it 'renders byte-identical XML parts and archive for the same input (RF-05, RNF-01)' do
    second = described_class.call(template_bytes: template_bytes, values: values)

    first_zip = Zip::File.open_buffer(rendered)
    second_zip = Zip::File.open_buffer(second)
    expect(second_zip.entries.map(&:name)).to eq(first_zip.entries.map(&:name))
    first_zip.entries.each { |entry| expect(second_zip.read(entry.name)).to eq(first_zip.read(entry.name)) }
    expect(second).to eq(rendered)
  end

  it 'keeps the template entry order' do
    expect(Zip::File.open_buffer(rendered).entries.map(&:name)).to eq(Zip::File.open_buffer(template_bytes).entries.map(&:name))
  end

  it 'raises ProposalRenderFailed with the names of an unknown placeholder left in the text (RF-08)' do
    bytes = scan_solo_docx(paragraphs: ['Valor {{VALOR_NUMERICO}}', 'Campo {{XYZ}}'])

    expect { described_class.call(template_bytes: bytes, values: values) }.to(raise_error do |error|
      expect(error.class.name).to eq('CustomExceptions::ScanSolo::ProposalRenderFailed')
      expect(error.placeholders).to eq(['XYZ'])
    end)
  end

  it 'raises ProposalRenderFailed for a placeholder split across 2 w:t (RF-08)' do
    bytes = scan_solo_docx(paragraphs: ['Valor {{VALOR_NUMERICO}}'], split: ['VALOR_NUMERICO'])

    expect { described_class.call(template_bytes: bytes, values: values) }.to(raise_error do |error|
      expect(error.class.name).to eq('CustomExceptions::ScanSolo::ProposalRenderFailed')
      expect(error.placeholders).to eq(['VALOR_NUMERICO'])
    end)
  end

  it 'does not take a {{NAME}} typed inside a value for a residual placeholder' do
    values['OBSERVACOES_COMERCIAIS'] = 'texto com {{XYZ}}'

    expect(document_xml).to include('texto com {{XYZ}}')
  end

  it 'raises ProposalRenderFailed for a file that is not a .docx (RF-08)' do
    expect { described_class.call(template_bytes: file_fixture('sample.pdf').binread, values: values) }
      .to(raise_error { |error| expect(error.class.name).to eq('CustomExceptions::ScanSolo::ProposalRenderFailed') })
  end

  it 'makes 0 HTTP requests and 0 LLM calls (RF-05, RNF-01)' do
    expect(ScanSolo::AiTurn::ModelInvoker).not_to receive(:new)
    expect(ScanSolo::AiTurn::ModelInvoker).not_to receive(:call)

    expect { rendered }.not_to raise_error
    expect(WebMock::RequestRegistry.instance.requested_signatures.hash).to be_empty
  end
end
