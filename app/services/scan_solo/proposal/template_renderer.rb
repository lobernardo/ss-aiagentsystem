# RF-05 / RF-06 / RF-08 / RNF-01: renders the `.docx` proposal template with
# the CT-03 values. Pure and deterministic: 0 HTTP, 0 LLM, 0 writes.
#
# Each `{{NAME}}` inside a single `w:t` of a text part (body, headers,
# footers) is replaced by its value, with control characters (except line
# breaks) removed and escaped as text by Nokogiri — never parsed as markup.
# Each line break of a value becomes a `w:br` followed by a new
# `w:t xml:space="preserve"` in the same `w:r`, so the run's `w:rPr` keeps
# applying. A placeholder left in the text (unknown name or split across
# `w:t`) or a result without a well-formed `word/document.xml` raises
# ProposalRenderFailed. The ZIP is rewritten in the template's entry order
# with a fixed mtime, so the same input yields the same bytes.
class ScanSolo::Proposal::TemplateRenderer
  PLACEHOLDER_TOKEN = /(\{\{[A-Z_]+\}\})/
  LINE_BREAK = /\r\n|\r|\n/
  CONTROL_CHARACTERS = /[[:cntrl:]&&[^\r\n]]/
  FIXED_MTIME = Zip::DOSTime.new(2000, 1, 1)
  NAMESPACES = ScanSolo::Proposal::TemplateDocument::NAMESPACES
  PATTERN = ScanSolo::Proposal::TemplateDocument::PATTERN

  def self.call(template_bytes:, values:)
    new(template_bytes: template_bytes, values: values).call
  end

  def initialize(template_bytes:, values:)
    @template_bytes = template_bytes
    @values = values
  end

  def call
    parts = ScanSolo::Proposal::TemplateDocument.new(template_bytes).parts
    residual = parts.values.flat_map { |document| residual_placeholders(document) }
    raise CustomExceptions::ScanSolo::ProposalRenderFailed.new(placeholders: residual.uniq.sort) if residual.any?

    parts.each_value { |document| document.xpath('//w:t', NAMESPACES).each { |text| render_text(text) } }
    rendered = write_zip(parts)
    ScanSolo::Proposal::TemplateDocument.new(rendered)
    rendered
  rescue CustomExceptions::ScanSolo::ProposalTemplateInvalid
    raise CustomExceptions::ScanSolo::ProposalRenderFailed
  end

  private

  attr_reader :template_bytes, :values

  # Placeholders that the substitution would leave behind, per paragraph:
  # known names inside a single `w:t` are dropped before joining the texts,
  # so values never count and split or unknown placeholders remain.
  def residual_placeholders(document)
    document.xpath('//w:p', NAMESPACES).flat_map do |paragraph|
      texts = paragraph.xpath('.//w:t', NAMESPACES).map do |text|
        text.text.gsub(PATTERN) { |token| values.key?(Regexp.last_match(1)) ? '' : token }
      end
      texts.join.scan(PATTERN).flatten
    end
  end

  def render_text(node)
    return unless node.text.match?(PATTERN)

    lines = rendered_lines(node.text)
    node['xml:space'] = 'preserve'
    node.content = lines.first
    lines.drop(1).reduce(node) do |previous, line|
      text = word_element(node, 't')
      text['xml:space'] = 'preserve'
      text.content = line
      previous.add_next_sibling(word_element(node, 'br')).add_next_sibling(text)
    end
  end

  # The `w:t` text with its placeholders replaced, split at the values' line
  # breaks (the template's own text is kept as is).
  def rendered_lines(text)
    text.split(PLACEHOLDER_TOKEN).each_with_object(['']) do |token, lines|
      name = token[PATTERN, 1]
      next lines[-1] += token unless name

      first, *rest = values.fetch(name).to_s.gsub(CONTROL_CHARACTERS, '').split(LINE_BREAK, -1)
      lines[-1] += first.to_s
      lines.concat(rest)
    end
  end

  def word_element(node, name)
    node.document.create_element(name).tap { |element| element.namespace = node.namespace }
  end

  def write_zip(parts)
    Zip::OutputStream.write_buffer(StringIO.new(+'')) do |output|
      Zip::File.open_buffer(template_bytes).entries.each do |entry|
        output.put_next_entry(Zip::Entry.new('', entry.name, time: FIXED_MTIME))
        document = parts[entry.name]
        output.write(document ? document.to_xml(save_with: Nokogiri::XML::Node::SaveOptions::AS_XML) : entry.get_input_stream.read)
      end
    end.string
  end
end
