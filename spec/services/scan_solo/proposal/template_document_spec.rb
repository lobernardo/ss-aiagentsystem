# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Proposal::TemplateDocument do
  let(:placeholders) { described_class::PLACEHOLDERS }
  let(:body_placeholders) { placeholders - ['NUMERO_PROPOSTA'] }

  describe 'CT-03: placeholder list' do
    it 'has the 16 v3 placeholders, without PROFUNDIDADE' do
      expect(placeholders.size).to eq(16)
      expect(placeholders.uniq.size).to eq(16)
      expect(placeholders).to include('TRECHO_PROFUNDIDADE', 'PRAZO_CRONOGRAMA', 'CONDICOES_PAGAMENTO', 'OBSERVACOES_COMERCIAIS')
      expect(placeholders).not_to include('PROFUNDIDADE')
    end
  end

  describe 'RF-17 (d–f): #validate!' do
    it 'accepts the 16 placeholders with one of them in the header' do
      document = described_class.new(scan_solo_docx_valid)

      expect { document.validate! }.not_to raise_error
      expect(document.parts.keys).to eq(%w[word/document.xml word/footer1.xml word/header1.xml])
    end

    it 'raises missing_placeholders with the absent names' do
      bytes = scan_solo_docx(paragraphs: (body_placeholders - ['VALOR_EXTENSO']).map { |name| "{{#{name}}}" },
                             header: '{{NUMERO_PROPOSTA}}')

      expect { described_class.new(bytes).validate! }.to(raise_error do |error|
        expect(error.class.name).to eq('CustomExceptions::ScanSolo::ProposalTemplateInvalid')
        expect(error.code).to eq('missing_placeholders')
        expect(error.placeholders).to eq(['VALOR_EXTENSO'])
      end)
    end

    it 'counts a placeholder that is only in the header or footer' do
      bytes = scan_solo_docx(paragraphs: body_placeholders.first(10).map { |name| "{{#{name}}}" },
                             header: '{{NUMERO_PROPOSTA}}', footer: body_placeholders.drop(10).map { |name| "{{#{name}}}" })

      expect { described_class.new(bytes).validate! }.not_to raise_error
    end

    it 'raises unknown_placeholders for {{XYZ}} and the retired {{PROFUNDIDADE}}, sorted and unique' do
      bytes = scan_solo_docx(paragraphs: body_placeholders.map { |name| "{{#{name}}}" } + ['{{XYZ}} e {{PROFUNDIDADE}}', '{{XYZ}}'],
                             header: '{{NUMERO_PROPOSTA}}')

      expect { described_class.new(bytes).validate! }.to(raise_error do |error|
        expect(error.class.name).to eq('CustomExceptions::ScanSolo::ProposalTemplateInvalid')
        expect(error.code).to eq('unknown_placeholders')
        expect(error.placeholders).to eq(%w[PROFUNDIDADE XYZ])
      end)
    end

    it 'raises split_placeholders when a placeholder spans 2 w:t' do
      expect { described_class.new(scan_solo_docx_valid(split: ['VALOR_EXTENSO'])).validate! }.to(raise_error do |error|
        expect(error.class.name).to eq('CustomExceptions::ScanSolo::ProposalTemplateInvalid')
        expect(error.code).to eq('split_placeholders')
        expect(error.placeholders).to eq(['VALOR_EXTENSO'])
      end)
    end

    it 'checks missing before split before unknown (CT-05 order)' do
      bytes = scan_solo_docx(paragraphs: (body_placeholders - ['VALOR_EXTENSO']).map { |name| "{{#{name}}}" } + ['{{XYZ}}'],
                             header: '{{NUMERO_PROPOSTA}}', split: ['VALOR_NUMERICO'])

      expect { described_class.new(bytes).validate! }.to(raise_error { |error| expect(error.code).to eq('missing_placeholders') })

      bytes = scan_solo_docx(paragraphs: body_placeholders.map { |name| "{{#{name}}}" } + ['{{XYZ}}'],
                             header: '{{NUMERO_PROPOSTA}}', split: ['VALOR_NUMERICO'])

      expect { described_class.new(bytes).validate! }.to(raise_error { |error| expect(error.code).to eq('split_placeholders') })
    end

    it 'never puts template text in the error message (RNF-04)' do
      bytes = scan_solo_docx(paragraphs: ['Texto confidencial sintético'], header: '{{NUMERO_PROPOSTA}}')

      expect { described_class.new(bytes).validate! }.to(raise_error do |error|
        expect(error.message).to eq('missing_placeholders')
      end)
    end
  end

  describe 'RF-17 (c): invalid_docx' do
    it 'refuses a PDF renamed to .docx' do
      expect { described_class.new(Rails.root.join('spec/fixtures/files/sample.pdf').binread) }.to(raise_error do |error|
        expect(error.class.name).to eq('CustomExceptions::ScanSolo::ProposalTemplateInvalid')
        expect(error.code).to eq('invalid_docx')
        expect(error.placeholders).to be_nil
      end)
    end

    it 'refuses a ZIP without word/document.xml' do
      bytes = Zip::OutputStream.write_buffer(StringIO.new(+'')) do |zip|
        zip.put_next_entry('word/header1.xml')
        zip.write('<w:hdr/>')
      end.string

      expect { described_class.new(bytes) }.to(raise_error { |error| expect(error.code).to eq('invalid_docx') })
    end

    it 'refuses a malformed XML part' do
      bytes = Zip::OutputStream.write_buffer(StringIO.new(+'')) do |zip|
        zip.put_next_entry('word/document.xml')
        zip.write('<w:document><w:body>')
      end.string

      expect { described_class.new(bytes) }.to(raise_error { |error| expect(error.code).to eq('invalid_docx') })
    end

    it 'refuses an archive above the uncompressed limit (RNF-06)' do
      stub_const("#{described_class}::MAX_UNCOMPRESSED_BYTES", 100)

      expect { described_class.new(scan_solo_docx_valid) }.to(raise_error { |error| expect(error.code).to eq('invalid_docx') })
    end
  end

  it 'RNF-04: no .docx file is versioned' do
    output, status = Open3.capture2('git', '-C', Rails.root.to_s, 'ls-files', '*.docx')

    expect(status).to be_success
    expect(output).to eq('')
  end
end
