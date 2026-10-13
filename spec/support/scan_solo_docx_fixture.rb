# frozen_string_literal: true

# RNF-04: synthetic `.docx` proposal templates built in memory — the
# repository never versions a real template. Reused by the template,
# renderer, local generation and upload specs.
#
# `scan_solo_docx(paragraphs:, header: nil, footer: nil, split: [])` builds a
# minimal valid document: each paragraph string becomes one `w:p` with a
# single run; `header`/`footer` (string or array) become `word/header1.xml`
# and `word/footer1.xml`. Every `{{NAME}}` whose NAME is in `split` is broken
# into 2 `w:t` (2 runs) inside its paragraph.
module ScanSoloDocxFixture
  WORD_NAMESPACE = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
  RELATIONSHIPS_NAMESPACE = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
  PACKAGE_RELATIONSHIPS_NAMESPACE = 'http://schemas.openxmlformats.org/package/2006/relationships'
  XML_DECLARATION = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'

  def scan_solo_docx(paragraphs:, header: nil, footer: nil, split: [])
    parts = { 'word/document.xml' => nil }
    parts['word/header1.xml'] = scan_solo_docx_part('hdr', Array(header), split) if header
    parts['word/footer1.xml'] = scan_solo_docx_part('ftr', Array(footer), split) if footer
    parts['word/document.xml'] = scan_solo_docx_part('document', paragraphs, split, parts.keys)

    Zip::OutputStream.write_buffer(StringIO.new(+'')) do |zip|
      {
        '[Content_Types].xml' => scan_solo_docx_content_types(parts.keys),
        '_rels/.rels' => scan_solo_docx_package_rels,
        'word/_rels/document.xml.rels' => scan_solo_docx_document_rels(parts.keys)
      }.merge(parts).each do |name, xml|
        zip.put_next_entry(name)
        zip.write(xml)
      end
    end.string
  end

  # The 16 CT-03 placeholders, `{{NUMERO_PROPOSTA}}` in the header and the
  # others one per body paragraph, with synthetic text around them.
  def scan_solo_docx_valid(split: [])
    body = (ScanSolo::Proposal::TemplateDocument::PLACEHOLDERS - ['NUMERO_PROPOSTA']).map { |name| "Campo sintético: {{#{name}}}." }
    scan_solo_docx(paragraphs: body, header: 'Proposta {{NUMERO_PROPOSTA}}', footer: 'Rodapé sintético', split: split)
  end

  private

  def scan_solo_docx_part(root, paragraphs, split, part_names = [])
    body = paragraphs.map { |text| "<w:p>#{scan_solo_docx_runs(text, split)}</w:p>" }.join
    body = "<w:body>#{body}#{scan_solo_docx_section(part_names)}</w:body>" if root == 'document'
    "#{XML_DECLARATION}<w:#{root} xmlns:w=\"#{WORD_NAMESPACE}\" xmlns:r=\"#{RELATIONSHIPS_NAMESPACE}\">#{body}</w:#{root}>"
  end

  # Header/footer references, with the relationship ids of scan_solo_docx_document_rels.
  def scan_solo_docx_section(part_names)
    references = (part_names - ['word/document.xml']).each_with_index.map do |name, index|
      type = name.include?('header') ? 'header' : 'footer'
      %(<w:#{type}Reference w:type="default" r:id="rId#{index + 1}"/>)
    end
    "<w:sectPr>#{references.join}</w:sectPr>"
  end

  def scan_solo_docx_runs(text, split)
    pieces = split.reduce([text]) do |chunks, name|
      chunks.flat_map do |chunk|
        chunk.split(/(?<=\{\{#{name[0, 2]})(?=#{name[2..]}\}\})/)
      end
    end
    pieces.map { |piece| %(<w:r><w:t xml:space="preserve">#{CGI.escapeHTML(piece)}</w:t></w:r>) }.join
  end

  def scan_solo_docx_content_types(part_names)
    overrides = part_names.map do |name|
      kind = File.basename(name, '.xml').sub(/\d+\z/, '')
      kind = 'document.main' if kind == 'document'
      %(<Override PartName="/#{name}" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.#{kind}+xml"/>)
    end
    defaults = '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>' \
               '<Default Extension="xml" ContentType="application/xml"/>'
    "#{XML_DECLARATION}<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">#{defaults}#{overrides.join}</Types>"
  end

  def scan_solo_docx_package_rels
    relationship = %(<Relationship Id="rId1" Type="#{RELATIONSHIPS_NAMESPACE}/officeDocument" Target="word/document.xml"/>)
    "#{XML_DECLARATION}<Relationships xmlns=\"#{PACKAGE_RELATIONSHIPS_NAMESPACE}\">#{relationship}</Relationships>"
  end

  def scan_solo_docx_document_rels(part_names)
    relationships = (part_names - ['word/document.xml']).each_with_index.map do |name, index|
      type = name.include?('header') ? 'header' : 'footer'
      %(<Relationship Id="rId#{index + 1}" Type="#{RELATIONSHIPS_NAMESPACE}/#{type}" Target="#{File.basename(name)}"/>)
    end
    "#{XML_DECLARATION}<Relationships xmlns=\"#{PACKAGE_RELATIONSHIPS_NAMESPACE}\">#{relationships.join}</Relationships>"
  end
end

RSpec.configure do |config|
  config.include ScanSoloDocxFixture
end
