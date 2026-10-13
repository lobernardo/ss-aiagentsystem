# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Quote::RequestEmail do
  let(:conversation_url) { 'https://app.example.com/app/accounts/1/conversations/7' }
  let(:map_link) { 'https://www.google.com/maps?q=-13.0053596,-55.9400673' }
  let(:values) do
    {
      'empresa' => 'AMAGGI Exportação e Importação Ltda.', 'nome' => 'Ana Souza', 'email' => 'ana@amaggi.com.br',
      'endereco_obra' => 'Rodovia BR-163, km 10', 'cidade_uf' => 'Lucas do Rio Verde/MT', 'tecnologia' => 'GPR',
      'tipo_intervencao' => 'Localizar tubulações antes da escavação'
    }
  end
  let(:inferred) { [] }
  let(:attachments) { [{ 'id' => 1, 'name' => 'planta_executiva.pdf', 'type' => 'PDF', 'file_type' => 'file', 'byte_size' => 2.megabytes }] }
  let(:snapshot) do
    {
      'fields' => ScanSolo::Quote::RequestEmail::Snapshot::FIELD_KEYS.index_with do |key|
        { 'value' => values[key], 'inferred' => inferred.include?(key) }
      end,
      'contact_name' => 'Ana Souza', 'phone' => nil, 'missing_labels' => [], 'validation_mode' => true, 'conversation_url' => conversation_url,
      'location_sources' => [map_link, 'https://www.google.com/maps?q=-13.00536,-55.94007'], 'attachments' => attachments
    }
  end
  let(:result) { described_class.render(snapshot: snapshot) }
  let(:email) { result.email }
  let(:lines) { email.text.split("\n") }
  let(:pending_labels) { (1..8).map { |index| I18n.t("scan_solo.quote.request_email.pending_items.#{index}") } }
  let(:closing_with_pending) { I18n.t('scan_solo.quote.request_email.closing_with_pending') }
  let(:closing_without_pending) { I18n.t('scan_solo.quote.request_email.closing_without_pending') }
  let(:validation_paragraph) { I18n.t('scan_solo.quote.request_email.validation_mode') }

  def body_lines(text)
    text.split("\n").take_while { |line| line != 'Instruções de resposta' }
  end

  it 'has the template version of RF-19' do
    expect(described_class::TEMPLATE_VERSION).to eq('quote_request_email.v2')
  end

  describe 'AMAGGI reference case (CT-01)' do
    it 'renders the subject, client data and location' do
      expect(email.subject).to eq('Solicitação de orçamento | AMAGGI | GeoRadar | Lucas do Rio Verde/MT')
      expect(lines).to include('Telefone/WhatsApp do solicitante: não informado', 'Tecnologia: GPR', 'Contato: Ana Souza')
      expect(lines[lines.index('Endereço informado: Rodovia BR-163, km 10') + 1]).to eq('Cidade/UF: Lucas do Rio Verde/MT')
      expect(email.text.scan('https://www.google.com/maps').size).to eq(1)
      expect(lines).to include("Localização informada pelo cliente (Google Maps): #{map_link}")
    end

    it 'renders the documents, the 8 pending items and the closing paragraph' do
      expect(email.text.scan('anexado a este e-mail').size).to eq(1)
      expect(lines).to include('- planta_executiva.pdf (PDF) — anexado a este e-mail.')
      expect(email.text).not_to include('DETALHES TÉCNICOS INFORMADOS', 'OUTRAS INFORMAÇÕES', 'Ponto 1')
      expect(lines.grep(/\A\* .+;\z/)).to eq(pending_labels.map { |label| "* #{label};" })
      expect(email.text).to include(closing_with_pending)
      expect(email.text).not_to include(closing_without_pending)
      expect(result.attachment_ids).to eq([1])
    end

    it 'follows the CT-01 section order and ends with the CT-04 instructions and empty block (RF-05, RF-11)' do
      titles = ['Olá, Luciano.', validation_paragraph, 'DADOS DO CLIENTE', 'LOCAL DO SERVIÇO', 'SERVIÇO SOLICITADO',
                'OBJETIVO DO LEVANTAMENTO', 'DOCUMENTAÇÃO RECEBIDA', 'INFORMAÇÕES AINDA NÃO CONFIRMADAS', closing_with_pending,
                "Conversa no ScanSOLO: #{conversation_url}", 'Atenciosamente,', 'Comercial ScanSolo', 'Instruções de resposta']

      expect(titles.map { |title| lines.index(title) }).to eq(titles.map { |title| lines.index(title) }.sort)
      expect(email.text).to end_with(ScanSolo::Quote::EmailComposer.empty_block)
      expect(email.text).to end_with(ScanSolo::Quote::EmailComposer.instruction_lines.join("\n"))
    end

    it 'renders the same subject, text and HTML twice (RF-01)' do
      second = described_class.render(snapshot: snapshot.deep_dup).email

      expect([second.subject, second.text, second.html]).to eq([email.subject, email.text, email.html])
    end
  end

  describe 'subject (RF-02, RF-17, RNF-02)' do
    it 'omits the city part without cidade_uf' do
      values.delete('cidade_uf')

      expect(email.subject).to eq('Solicitação de orçamento | AMAGGI | GeoRadar')
      expect(lines.grep(%r{\ACidade/UF:})).to be_empty
    end

    it 'omits the city part without a known UF and still quotes cidade_uf in the body' do
      values['cidade_uf'] = 'Zona rural'

      expect(email.subject).to eq('Solicitação de orçamento | AMAGGI | GeoRadar')
      expect(lines).to include('Cidade/UF: Zona rural')
    end

    it 'accepts -, comma and space separators' do
      { 'Sorriso - mt' => 'Sorriso/MT', 'Campinas, SP' => 'Campinas/SP', 'Belo Horizonte MG' => 'Belo Horizonte/MG' }.each do |raw, part|
        snapshot['fields']['cidade_uf']['value'] = raw

        expect(described_class.render(snapshot: snapshot).email.subject).to eq("Solicitação de orçamento | AMAGGI | GeoRadar | #{part}")
      end
    end

    [0, 1, 300, 500].each do |size|
      it "stays within 120 characters without control characters for #{size}-character values" do
        long = "#{'Á' * size}\r\n\tX"
        values.merge!('empresa' => long, 'cidade_uf' => "#{long}/MT")
        subject = email.subject

        expect(subject.length).to be <= 120
        expect(subject).not_to match(/[[:cntrl:]]/)
        expect(subject.split(' | ')[2]).to eq('GeoRadar')
      end
    end

    it 'truncates the company first, with an ellipsis' do
      values['empresa'] = 'B' * 300
      subject = email.subject

      expect(subject.length).to eq(120)
      expect(subject).to end_with('… | GeoRadar | Lucas do Rio Verde/MT')
    end

    it 'falls back to the contact name without a company' do
      values.delete('empresa')

      expect(email.subject).to eq('Solicitação de orçamento | Ana Souza | GeoRadar | Lucas do Rio Verde/MT')
      expect(lines).to include('Empresa: não informado')
    end

    it 'escapes HTML and strips header injection (RF-17)' do
      values['empresa'] = "<script>x</script>\r\nBcc: a@b.c"

      expect(email.html).to include('Empresa: &lt;script&gt;x&lt;/script&gt;')
      expect(email.html).not_to include('<script>')
      expect(email.subject).not_to match(/[\r\n]/)
    end
  end

  describe 'service (RF-04)' do
    it 'renders "Serviço não informado" in the subject, the section and the pending list' do
      values.delete('tecnologia')

      expect(email.subject).to eq('Solicitação de orçamento | AMAGGI | Serviço não informado | Lucas do Rio Verde/MT')
      expect(lines[lines.index('SERVIÇO SOLICITADO') + 1]).to eq('Serviço não informado')
      expect(lines).to include('* Tipo de serviço;')
    end

    it 'keeps a free-text service label whole and lists the service lines' do
      values.merge!('tecnologia' => nil, 'tipo_servico' => 'Sondagem SPT', 'interferencias_buscadas' => 'Tubulações')

      expect(email.subject).to eq('Solicitação de orçamento | AMAGGI | Sondagem SPT | Lucas do Rio Verde/MT')
      expect(lines).to include('Tipo de serviço: Sondagem SPT', 'Interferências buscadas: Tubulações')
      expect(email.text).not_to include('Serviço não informado')
    end
  end

  describe 'optional lines and sections (RF-05, RF-06, RF-07)' do
    it 'omits empty optional lines and the technical section' do
      values.delete('nome')

      expect(lines.grep(%r{\A(CNPJ|Unidade / cliente final|Contato):})).to be_empty
      expect(email.text).not_to include('DETALHES TÉCNICOS INFORMADOS')
      expect(body_lines(email.text).grep(/\A[^:]+:\z/)).to eq(['No geral, seguem os dados coletados do lead:'])
    end

    it 'renders the optional client and location lines with values' do
      values.merge!('cnpj' => '11.111.111/0001-11', 'cliente_final' => 'Unidade Sorriso', 'bairro' => 'Centro')
      snapshot['phone'] = '+5565999990000'

      expect(lines).to include('CNPJ: 11.111.111/0001-11', 'Unidade / cliente final: Unidade Sorriso',
                               'Endereço informado: Rodovia BR-163, km 10, Centro', 'Telefone/WhatsApp do solicitante: +5565999990000')
    end

    it 'does not repeat a bairro already in the address' do
      values.merge!('endereco_obra' => 'Rua A, 10, centro', 'bairro' => 'Centro')

      expect(lines).to include('Endereço informado: Rua A, 10, centro')
    end

    it 'keeps the address line after the bairro rule extraction (proposta-template-local T20)' do
      values.merge!('endereco_obra' => 'Rua São José, 10', 'bairro' => 'Jardim Europa')
      inferred.push('endereco_obra', 'bairro')

      expect(lines).to include('Endereço informado: Rua São José, 10 (a confirmar), Jardim Europa (a confirmar)')
    end

    it 'compares the bairro without accents' do
      values.merge!('endereco_obra' => 'Rua A, 10, Jardim Sao Jose', 'bairro' => 'Jardim São José')

      expect(lines).to include('Endereço informado: Rua A, 10, Jardim Sao Jose')
    end

    it 'shows a bairro alone when there is no address' do
      values.delete('endereco_obra')
      values['bairro'] = 'Jardim São José'

      expect(lines).to include('Endereço informado: Jardim São José')
    end
  end

  describe '.address_with_district (CT-02, shared with the proposal template)' do
    it 'appends the district only when the street does not mention it, ignoring case and accents' do
      expect(described_class.address_with_district('Rua A, 10', 'Centro')).to eq('Rua A, 10, Centro')
      expect(described_class.address_with_district('Rua A, 10 - CENTRO', 'Centro')).to eq('Rua A, 10 - CENTRO')
      expect(described_class.address_with_district('Rua A, Sao Jose', 'São José')).to eq('Rua A, Sao Jose')
      expect(described_class.address_with_district('Rua A, 10', nil)).to eq('Rua A, 10')
      expect(described_class.address_with_district(nil, 'Centro')).to eq('Centro')
      expect(described_class.address_with_district(nil, nil)).to be_nil
    end

    it 'renders the technical section with at least one value' do
      values.merge!('profundidade' => '3 m', 'prazo_desejado' => '30 dias')

      expect(lines.each_cons(3)).to include(['DETALHES TÉCNICOS INFORMADOS', 'Profundidade de interesse: 3 m', 'Prazo desejado: 30 dias'])
    end

    it 'lists only the filled other keys, in catalog order, before the documentation (M-03)' do
      values.merge!('condicoes_especiais' => 'NF até dia 20', 'metragem' => '200 m')

      section = lines[lines.index('OUTRAS INFORMAÇÕES')..]
      expect(section.take(3)).to eq(['OUTRAS INFORMAÇÕES', 'Metragem: 200 m', 'Condições especiais: NF até dia 20'])
      expect(lines.index('OUTRAS INFORMAÇÕES')).to be < lines.index('DOCUMENTAÇÃO RECEBIDA')
    end

    it 'quotes lead text as is, marks inferido values and never says "(extraído da conversa)"' do
      values['tipo_intervencao'] = 'localizar tubulações enterradas <b>antes</b> da escavação'
      inferred << 'cnpj'
      values['cnpj'] = '11.111.111/0001-11'

      expect(lines).to include('localizar tubulações enterradas <b>antes</b> da escavação', 'CNPJ: 11.111.111/0001-11 (a confirmar)')
      expect(email.html).to include('&lt;b&gt;antes&lt;/b&gt;')
      expect(email.text).not_to include('(extraído da conversa)')
    end

    it 'says "não informado" for an empty objective' do
      values.delete('tipo_intervencao')

      expect(lines[lines.index('OBJETIVO DO LEVANTAMENTO') + 1]).to eq('não informado')
    end
  end

  describe 'location (RF-10)' do
    it 'labels distinct points and drops non-https or unknown hosts' do
      snapshot['location_sources'] = [map_link, 'http://evil.example/maps?q=1,1', 'https://www.google.com/maps?q=-13.0233596,-55.9400673']

      expect(lines).to include("Localização informada pelo cliente (Google Maps): Ponto 1: #{map_link}; " \
                               'Ponto 2: https://www.google.com/maps?q=-13.0233596,-55.9400673')
      expect(email.text).not_to include('evil.example')
    end

    it 'omits the location line without links' do
      snapshot['location_sources'] = []

      expect(email.text).not_to include('Localização informada')
    end
  end

  describe 'documents (RF-13, RNF-03)' do
    let(:attachments) do
      [{ 'id' => 1, 'name' => 'a.pdf', 'type' => 'PDF', 'file_type' => 'file', 'byte_size' => 10.megabytes },
       { 'id' => 2, 'name' => 'b.jpg', 'type' => 'JPG', 'file_type' => 'image', 'byte_size' => 8.megabytes },
       { 'id' => 3, 'name' => 'c.txt', 'type' => 'TXT', 'file_type' => 'file', 'byte_size' => 1.megabyte }]
    end

    it 'attaches while the total stays within 15 MB and links the rest' do
      expect(lines).to include('- a.pdf (PDF) — anexado a este e-mail.', "- b.jpg (JPG) — disponível na conversa: #{conversation_url}",
                               "- c.txt (TXT) — disponível na conversa: #{conversation_url}")
      expect(result.attachment_ids).to eq([1])
    end

    it 'never attaches a file above 15 MB' do
      attachments.replace([{ 'id' => 4, 'name' => 'big.zip', 'type' => 'ZIP', 'file_type' => 'file', 'byte_size' => 16.megabytes }])

      expect(result.attachment_ids).to be_empty
      expect(email.text).not_to include('anexado a este e-mail')
    end

    it 'restricts the candidates to the given attachment ids' do
      result = described_class.render(snapshot: snapshot, attachment_ids: [2, 3])

      expect(result.attachment_ids).to eq([2, 3])
      expect(result.email.text).to include("- a.pdf (PDF) — disponível na conversa: #{conversation_url}")
    end

    it 'says no documents were received without attachments' do
      attachments.clear

      expect(lines[lines.index('DOCUMENTAÇÃO RECEBIDA') + 1]).to eq('Nenhum documento recebido até o momento.')
    end
  end

  describe 'pending items and closing paragraph (RF-08, RF-09)' do
    it 'omits the pending section and uses the "sem pendências" paragraph when everything is informed' do
      values.merge!('area' => '800 m²', 'profundidade' => '3 m', 'integracao_seguranca' => 'Sim', 'restricoes_acesso' => 'Crachá',
                    'prazo_desejado' => '30 dias', 'condicoes_especiais' => 'NF até dia 20')
      attachments.push({ 'id' => 2, 'name' => 'foto.jpg', 'type' => 'JPG', 'file_type' => 'image', 'byte_size' => 1 },
                       { 'id' => 3, 'name' => 'area.kmz', 'type' => 'KMZ', 'file_type' => 'file', 'byte_size' => 1 })

      expect(email.text).not_to include('INFORMAÇÕES AINDA NÃO CONFIRMADAS', closing_with_pending)
      expect(email.text.scan(closing_without_pending).size).to eq(1)
    end

    it 'appends the config missing labels' do
      snapshot['missing_labels'] = ['CNPJ']

      expect(lines.grep(/\A\* /).last).to eq('* CNPJ;')
      expect(email.text.scan(closing_with_pending).size).to eq(1)
    end
  end

  describe 'nao_informado (proposta-template-local RF-31)' do
    # As built by RequestEmail::Snapshot: no value, the status and the label only.
    let(:not_informed) { { 'profundidade' => 'Profundidade de investigação' } }
    let(:snapshot) do
      {
        'fields' => ScanSolo::Quote::RequestEmail::Snapshot::FIELD_KEYS.index_with do |key|
          not_informed.key?(key) ? { 'value' => nil, 'inferred' => false, 'not_informed' => true } : { 'value' => values[key], 'inferred' => false }
        end,
        'contact_name' => 'Ana Souza', 'phone' => nil, 'missing_labels' => [],
        'not_informed' => not_informed.map { |key, label| { 'key' => key, 'label' => label } },
        'validation_mode' => true, 'conversation_url' => conversation_url, 'location_sources' => [], 'attachments' => attachments
      }
    end

    before do
      values.merge!('area' => '800 m²', 'integracao_seguranca' => 'Sim', 'restricoes_acesso' => 'Crachá', 'prazo_desejado' => '30 dias',
                    'condicoes_especiais' => 'NF até dia 20')
      attachments.push({ 'id' => 2, 'name' => 'foto.jpg', 'type' => 'JPG', 'file_type' => 'image', 'byte_size' => 1 },
                       { 'id' => 3, 'name' => 'area.kmz', 'type' => 'KMZ', 'file_type' => 'file', 'byte_size' => 1 })
    end

    it 'renders the required field as not informed and lists its fixed item once with the suffix' do
      expect(lines).to include('Profundidade de investigação: Não informado pelo cliente')
      expect(lines.grep(/\A\* /)).to eq(['* Profundidade-alvo de investigação (cliente não soube informar);'])
      expect(email.text).not_to include('não sei')
    end

    it 'keeps item 1 with the suffix when area is nao_informado and metragem is absent' do
      values.delete('area')
      not_informed['area'] = 'Área'

      expect(lines.grep(/\A\* /)).to include("* #{pending_labels[0]} (cliente não soube informar);")
    end

    it 'lists the area label when metragem informs item 1' do
      values.delete('area')
      values['metragem'] = '200 m'
      not_informed['area'] = 'Área'

      expect(lines.grep(/\A\* /)).not_to include(a_string_starting_with("* #{pending_labels[0]}"))
      expect(lines.grep(/\A\* /)).to include('* Área (cliente não soube informar);')
    end

    it 'renders an optional nao_informado line' do
      values.delete('condicoes_especiais')
      not_informed['condicoes_especiais'] = 'Condições especiais'

      expect(lines).to include('Condições especiais: Não informado pelo cliente')
    end

    it 'renders the same text and HTML twice' do
      second = described_class.render(snapshot: snapshot.deep_dup).email

      expect([second.text, second.html]).to eq([email.text, email.html])
    end
  end

  describe 'validation mode (RF-12)' do
    it 'renders the paragraph right after the opening when on' do
      expect(lines.take(5)).to eq(['Olá, Luciano.', '', I18n.t('scan_solo.quote.request_email.intro'), validation_paragraph,
                                   'No geral, seguem os dados coletados do lead:'])
    end

    it 'omits the paragraph when off' do
      snapshot['validation_mode'] = false

      expect(email.text.scan(validation_paragraph).size).to eq(0)
    end
  end

  describe 'reply block safety (RF-11)' do
    it 'parses no value from the e-mail, even with lead lines imitating the CT-04 block' do
      values['tipo_intervencao'] = "Valor total: 10\n- Prazo/cronograma: 5 dias\n=== FIM ==="
      values['condicoes_especiais'] = 'Condições de pagamento: à vista'

      parsed = ScanSolo::Quote::ResponseBlockParser.call(content: email.text)
      expect(parsed.values.values).to all(be_nil)
      expect(lines).to include('» Valor total: 10', '» - Prazo/cronograma: 5 dias', '» === FIM ===',
                               'Condições especiais: Condições de pagamento: à vista')
      expect(email.text).to end_with(ScanSolo::Quote::EmailComposer.empty_block)
    end

    it 'parses no value from the plain AMAGGI e-mail' do
      expect(ScanSolo::Quote::ResponseBlockParser.call(content: email.text).values.values).to all(be_nil)
    end
  end

  describe 'HTML (RF-16, RF-17)' do
    it 'breaks lines with <br> and links only the map and conversation URLs' do
      values['observacoes_tecnicas'] = 'ver https://evil.example/x'

      hrefs = email.html.scan(/href="([^"]*)"/).flatten
      expect(hrefs).to contain_exactly(map_link, conversation_url)
      expect(email.html).to include('Olá, Luciano.<br><br>', 'ver https://evil.example/x')
    end
  end

  describe '.render_update (CT-03, RF-14)' do
    let(:previous) { snapshot.deep_dup }

    it 'lists the changes, the full summary and the block' do
      previous
      snapshot['fields']['profundidade']['value'] = '3 m'
      update = described_class.render_update(snapshot: snapshot, previous: previous)
      update_lines = update.email.text.split("\n")

      expect(update.email.subject).to be_nil
      expect(update_lines.first).to eq('Atualização:')
      expect(update_lines).to include('Profundidade de interesse: não informado → 3 m', a_string_starting_with('INFORMAÇÕES AINDA NÃO CONFIRMADAS: '))
      expect(update_lines.index('DADOS DO CLIENTE')).to be > update_lines.index('Profundidade de interesse: não informado → 3 m')
      expect(update_lines).to include('Comercial ScanSolo', 'DETALHES TÉCNICOS INFORMADOS')
      expect(update_lines).not_to include('Olá, Luciano.')
      expect(update.email.text).to end_with(ScanSolo::Quote::EmailComposer.empty_block)
    end

    it 'attaches only new attachments and lists them' do
      attachments << { 'id' => 2, 'name' => 'foto.jpg', 'type' => 'JPG', 'file_type' => 'image', 'byte_size' => 2.megabytes }
      previous['attachments'] = previous['attachments'].take(1)
      update = described_class.render_update(snapshot: snapshot, previous: previous)

      expect(update.attachment_ids).to eq([2])
      expect(update.email.text).to include('Novo anexo: foto.jpg (JPG)', '- foto.jpg (JPG) — anexado a este e-mail.',
                                           "- planta_executiva.pdf (PDF) — disponível na conversa: #{conversation_url}")
    end

    it 'detects rendered changes only' do
      expect(described_class.changed?(snapshot, previous)).to be(false)

      snapshot['conversation_url'] = 'https://app.example.com/other'
      expect(described_class.changed?(snapshot, previous)).to be(false)

      snapshot['fields']['area']['value'] = '800 m²'
      expect(described_class.changed?(snapshot, previous)).to be(true)
    end
  end
end
