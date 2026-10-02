# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Quote::ResponseBlockParser do
  let(:quoted_empty_block) { ScanSolo::Quote::EmailComposer.empty_block.lines.map { |line| "> #{line}" }.join }
  let(:quote_header) { 'Em qua., 1 de out. de 2026 às 10:00, ScanSolo <atendimento.comercial@scansolo.com.br> escreveu:' }
  let(:expected_values) do
    { total_value: BigDecimal('12500.00'), schedule: '10 dias úteis', scope: "Varredura GPR\nem 3 áreas\ncom relatório",
      payment_terms: '50% na aprovação, 50% na entrega', notes: 'Validade de 15 dias' }
  end
  let(:reply) do
    <<~TEXT
      Segue o orçamento.

      === RESPOSTA DO ORÇAMENTO ===
      Valor total: R$ 12.500,00
      Prazo/cronograma: 10 dias úteis
      Escopo/atividades: Varredura GPR
      em 3 áreas
      com relatório
      Condições de pagamento: 50% na aprovação, 50% na entrega
      Observações comerciais: Validade de 15 dias
      === FIM ===

      #{quote_header}
      #{quoted_empty_block}
    TEXT
  end

  before do
    allow(ScanSolo::AiTurn::ModelInvoker).to receive(:call).and_raise('LLM must not be called (RF-21)')
    allow(RubyLLM).to receive(:context).and_raise('LLM must not be called (RF-21)')
  end

  it 'reads the reply above the quoted empty block, trimmed, with the value as a decimal (RF-17)' do
    result = described_class.call(content: reply)

    expect(result).to be_valid
    expect(result.values).to eq(expected_values)
    expect(result.values[:total_value].to_s('F')).to eq('12500.0')
    expect(ScanSolo::AiTurn::ModelInvoker).not_to have_received(:call)
    expect(RubyLLM).not_to have_received(:context)
  end

  {
    'lower case without accents' => <<~TEXT,
      valor total: r$ 12.500,00
      prazo/cronograma: 10 dias úteis
      escopo/atividades: Varredura GPR
      em 3 áreas
      com relatório
      condicoes de pagamento: 50% na aprovação, 50% na entrega
      observacoes comerciais: Validade de 15 dias
    TEXT
    'extra spaces, blank lines and no delimiters' => <<~TEXT,
      Valor   total :   R$ 12.500,00


      Prazo / cronograma:10 dias úteis

      Escopo/atividades:   Varredura GPR
      em 3 áreas
      com relatório

      Condições de pagamento :  50% na aprovação, 50% na entrega
      Observações comerciais: Validade de 15 dias
    TEXT
    'bold labels and list markers from HTML' => <<~TEXT
      === RESPOSTA DO ORÇAMENTO ===
      **Valor total:** R$ 12.500,00
      - Prazo/cronograma: 10 dias úteis
      • **Escopo/atividades:** Varredura GPR
      em 3 áreas
      com relatório
      * Condições de pagamento: 50% na aprovação, 50% na entrega
      _Observações comerciais:_ Validade de 15 dias
      === FIM ===
    TEXT
  }.each do |variation, block|
    it "reads the same values with #{variation} (CT-04)" do
      result = described_class.call(content: "#{block}\n#{quote_header}\n#{quoted_empty_block}")

      expect(result).to be_valid
      expect(result.values).to eq(expected_values)
    end
  end

  it 'ignores an unprefixed quoted empty block below the reply (Outlook style)' do
    content = reply.sub(quote_header, "-----Original Message-----\nDe: ScanSolo").sub(quoted_empty_block, ScanSolo::Quote::EmailComposer.empty_block)

    expect(described_class.call(content: content).values).to eq(expected_values)
  end

  it 'ends a value at a quote header wrapped over two lines' do
    content = reply.sub(quote_header, "Em qua., 1 de out. de 2026 às 10:00, ScanSolo\n<atendimento.comercial@scansolo.com.br> escreveu:")
                   .sub('Observações comerciais: Validade de 15 dias', 'Observações comerciais: Em até 3 parcelas')
                   .sub("=== FIM ===\n", '')

    expect(described_class.call(content: content).values[:notes]).to eq('Em até 3 parcelas')
  end

  {
    'a dot decimal value' => '12500.00',
    'a zero value' => '0,00',
    'a value with text' => 'R$ 12.500,00 à vista'
  }.each do |case_name, value|
    it "flags only total_value for #{case_name} (RF-18)" do
      result = described_class.call(content: reply.sub('R$ 12.500,00', value))

      expect(result).not_to be_valid
      expect(result.problems).to eq([:total_value])
    end
  end

  it 'flags payment_terms when its label is missing (RF-18)' do
    result = described_class.call(content: reply.sub("Condições de pagamento: 50% na aprovação, 50% na entrega\n", ''))

    expect(result.problems).to eq([:payment_terms])
  end

  it 'flags the 4 required fields when only the quoted empty block is present (RF-18)' do
    result = described_class.call(content: "Obrigado!\n\n#{quote_header}\n#{quoted_empty_block}")

    expect(result.problems).to eq(%i[total_value schedule scope payment_terms])
    expect(result.values.values).to all(be_nil)
  end

  it 'accepts a missing optional note' do
    result = described_class.call(content: reply.sub('Validade de 15 dias', ''))

    expect(result).to be_valid
    expect(result.values[:notes]).to be_nil
  end

  it 'converts the HTML when the text content is empty (CT-04)' do
    html = '<div>Segue.</div><div><b>Valor total:</b> R$ 12.500,00<br>Prazo/cronograma: 10 dias &uacute;teis<br>' \
           'Escopo/atividades: Varredura GPR<br>em 3 &aacute;reas<br>com relat&oacute;rio</div>' \
           '<p><strong>Condições de pagamento:</strong> 50% na aprovação, 50% na entrega</p>' \
           '<ul><li>Observações comerciais: Validade de 15 dias</li></ul>' \
           "<div>#{quote_header}</div><blockquote>#{ScanSolo::Quote::EmailComposer.empty_block.gsub("\n", '<br>')}</blockquote>"

    expect(described_class.call(content: '', html: html).values).to eq(expected_values)
  end
end
