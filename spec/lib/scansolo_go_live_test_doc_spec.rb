require 'rails_helper'

# Documentation checks for the controlled go-live test script (RF-62) rather
# than a spec for a single class.
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'ScanSolo go-live test documentation' do
  let(:content) { Rails.root.join('docs/runbooks/SCANSOLO_GO_LIVE_TEST.md').read }
  let(:criteria) { content.split(/^### (?=\d+\. )/).drop(1) }

  it 'lists the 12 go-live criteria numbered in order' do
    expect(criteria.map { |criterion| criterion[/\A(\d+)\./, 1] }).to eq((1..12).map(&:to_s))
  end

  it 'gives every criterion an action, an evidence and a binary pass condition' do
    criteria.each do |criterion|
      expect(criterion).to include('**Ação**:', '**Evidência**:', '**Passa se**:')
    end
  end

  it 'covers each go-live criterion' do
    titles = criteria.map { |criterion| criterion.lines.first.strip }

    expect(titles).to eq([
                           '1. Mensagem real chega',
                           '2. Exatamente um turno',
                           '3. Exatamente uma resposta',
                           '4. RAG usado',
                           '5. Oportunidade criada',
                           '6. Estágio correto',
                           '7. Cadência coerente',
                           '8. Resposta humana pausa a IA',
                           '9. Devolver à IA funciona',
                           '10. Nenhuma proposta mock',
                           '11. Logs e correlation id',
                           '12. Nenhum envio duplicado'
                         ])
  end

  it 'reserves the human gates section' do
    expect(content).to match(/^## Gates humanos$/)
  end
end
# rubocop:enable RSpec/DescribeClass
