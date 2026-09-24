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
    expect(criteria).to all(include('**Ação**:', '**Evidência**:', '**Passa se**:'))
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

  describe 'human gates' do
    let(:gates) do
      content[/^## Gates humanos$.*/m].split(/^### (?=HG-\d{2} )/).drop(1).index_by { |gate| gate[/\AHG-\d{2}/] }
    end

    it 'gives every gate an owner, what it unblocks, a verification and an unchecked signature' do
      expect(gates.values).to all(include('**Dono**:', '**Desbloqueia**:', '**Verificação**:').and(match(/^- \*\*Assinatura\*\*: \[ \]/)))
    end

    it 'documents the AI activation gates HG-01, HG-06 and HG-09' do
      expect(gates.keys).to include('HG-01', 'HG-06', 'HG-09')
      expect(gates['HG-01']).to include('Admin Meta', 'App Secret', 'webhook assinado')
      expect(gates['HG-06']).to include('Produto + Ops', '`status.agent.allowed_inbox_ids` não vazio', '`status.inbox_conflicts == []`')
      expect(gates['HG-09']).to include('**Dono**: Ops.', '`status.llm_key_configured == true`', '`succeeded`')
    end

    it 'documents the Meta templates and Make integration gates HG-02 and HG-03' do
      expect(gates.keys).to include('HG-02', 'HG-03')
      expect(gates['HG-02']).to include('Produto + Admin Meta', '`GET /scan_solo/cadence_templates`', '`blocked`')
      expect(gates['HG-03']).to include('Dono do Make + Ops', '`scan_solo.make.scenario_url`', '`scan_solo.make.secret`',
                                        '`scan_solo.make.inbound_signing_secret`', 'master key', '`status.proposal_integration == "configured"`',
                                        '`action`')
    end

    it 'documents the SMTP, LEXUS, roles and VPS diff gates HG-04, HG-05, HG-07 and HG-08' do
      expect(gates.keys).to include('HG-04', 'HG-05', 'HG-07', 'HG-08')
      expect(gates['HG-04']).to include('**Dono**: Ops.', 'SMTP', '`.env` da VPS', 'convite')
      expect(gates['HG-05']).to include('Dono LEXUS + Ops', '`docs/runbooks/PRODUCTION_CUTOVER.md`', '`scansolo_enabled`')
      expect(gates['HG-07']).to include('**Dono**: Produto/Gestão.', 'administradores')
      expect(gates['HG-08']).to include('**Dono**: Ops.', 'passo 1', 'tags de imagem', 'Git')
    end

    it 'documents the go-live sign-off and PDF/crawler scope gates HG-10 and HG-11' do
      expect(gates.keys).to include('HG-10', 'HG-11')
      expect(gates['HG-10']).to include('Produto + Ops', '12 critérios', 'todos os 12 "Passa"')
      expect(gates['HG-11']).to include('Produto + Dev', 'RF-47 não é implementado',
                                        'somente via `SafeFetch` + `ssrf_filter`', 'allowlist de domínio')
    end

    it 'lists every human gate HG-01..HG-11 in order' do
      expect(gates.keys).to eq((1..11).map { |number| format('HG-%02d', number) })
    end
  end
end
# rubocop:enable RSpec/DescribeClass
