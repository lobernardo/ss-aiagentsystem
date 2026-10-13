# RF-17 (c–f), RF-08, CT-03, CT-05, RNF-06: reads a `.docx` proposal template
# and validates its placeholders. Pure: 0 writes, 0 HTTP, 0 LLM.
#
# `new(bytes)` opens the ZIP and parses its text parts (body, headers,
# footers) with a strict XML parser; an invalid ZIP, a missing
# `word/document.xml`, a malformed XML part or an archive above the
# uncompressed limit raises ProposalTemplateInvalid `invalid_docx`.
#
# `validate!` scans each paragraph (`w:p`), joining the text of its `w:t`
# elements, and raises — in the CT-05 order — `missing_placeholders`,
# `split_placeholders` (one occurrence spread over 2+ `w:t`) or
# `unknown_placeholders` (outside PLACEHOLDERS). Errors carry only names.
class ScanSolo::Proposal::TemplateDocument
  # CT-03, in table order: the 16 placeholders of the v3 template, all required.
  PLACEHOLDERS = %w[
    NUMERO_PROPOSTA DATA_PROPOSTA DATA_SOLICITACAO NOME_EMPRESA NOME_CONTATO PROJETO_CLIENTE_FINAL ENDERECO_OBRA CIDADE_ESTADO
    RUA_CIDADE_ESTADO DESCRICAO_ESCOPO PRAZO_CRONOGRAMA CONDICOES_PAGAMENTO OBSERVACOES_COMERCIAIS TRECHO_PROFUNDIDADE
    VALOR_NUMERICO VALOR_EXTENSO
  ].freeze
  PATTERN = /\{\{([A-Z_]+)\}\}/
  DOCUMENT_PART = 'word/document.xml'.freeze
  TEXT_PARTS = %r{\Aword/(document|header\d*|footer\d*)\.xml\z}
  # ZIP bomb guard: total declared uncompressed size of the archive.
  MAX_UNCOMPRESSED_BYTES = 100 * 1024 * 1024
  NAMESPACES = { 'w' => 'http://schemas.openxmlformats.org/wordprocessingml/2006/main' }.freeze

  # { part name => Nokogiri::XML::Document } of the text parts.
  attr_reader :parts

  def initialize(bytes)
    zip = Zip::File.open_buffer(bytes)
    invalid! if zip.find_entry(DOCUMENT_PART).nil? || zip.entries.sum(&:size) > MAX_UNCOMPRESSED_BYTES

    @parts = text_parts(zip)
  rescue Zip::Error, Nokogiri::XML::SyntaxError
    invalid!
  end

  def validate!
    found = []
    split = []
    parts.each_value do |document|
      paragraphs(document).each do |texts|
        scan_paragraph(texts, found, split)
      end
    end

    raise_invalid!('missing_placeholders', PLACEHOLDERS - found)
    raise_invalid!('split_placeholders', split)
    raise_invalid!('unknown_placeholders', found - PLACEHOLDERS)
  end

  private

  def text_parts(zip)
    zip.entries.select { |entry| entry.name.match?(TEXT_PARTS) }.sort_by(&:name).to_h do |entry|
      [entry.name, Nokogiri::XML(entry.get_input_stream.read, &:strict)]
    end
  end

  # The `w:t` texts of each paragraph; a `w:t` belongs to its nearest `w:p`
  # (paragraphs nested in text boxes are scanned on their own).
  def paragraphs(document)
    document.xpath('//w:t', NAMESPACES).group_by { |text| text.at_xpath('ancestor::w:p[1]', NAMESPACES) }.values.map do |texts|
      texts.map(&:text)
    end
  end

  def scan_paragraph(texts, found, split)
    run_ends = texts.each_with_object([]) { |text, ends| ends << ((ends.last || 0) + text.length) }
    texts.join.scan(PATTERN) do
      match = Regexp.last_match
      found << match[1]
      first_run = run_ends.index { |run_end| run_end > match.begin(0) }
      last_run = run_ends.index { |run_end| run_end >= match.end(0) }
      split << match[1] if first_run != last_run
    end
  end

  def raise_invalid!(code, names)
    return if names.empty?

    raise CustomExceptions::ScanSolo::ProposalTemplateInvalid.new(code, placeholders: names.uniq.sort)
  end

  def invalid!
    raise CustomExceptions::ScanSolo::ProposalTemplateInvalid, 'invalid_docx'
  end
end
