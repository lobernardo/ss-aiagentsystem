# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'scan_solo.quote.request_email texts' do # rubocop:disable RSpec/DescribeClass
  let(:texts) { I18n.t('scan_solo.quote.request_email') }
  let(:leaves) do
    flatten = lambda do |value, path|
      value.is_a?(Hash) ? value.flat_map { |key, child| flatten.call(child, [*path, key]) } : [[path.join('.'), value]]
    end
    flatten.call(texts, []).to_h
  end
  let(:forbidden) do
    { 'R$' => /R\$/, 'IA' => /\bIA\b/, 'inteligência artificial' => /intelig[êe]ncia artificial/i,
      'sistema' => /sistema/i, 'token' => /token/i, 'http' => /http/i }
  end

  it 'has no price, AI, system, secret or link mention in the fixed texts (RF-16)' do
    offenders = leaves.except('validation_mode').flat_map do |key, text|
      forbidden.filter_map { |name, pattern| "#{key}: #{name}" if text.match?(pattern) }
    end

    expect(offenders).to be_empty
  end

  it 'keeps the approved validation mode paragraph literally (RF-12)' do
    expect(texts[:validation_mode]).to eq(
      'Nesse primeiro momento estou aprendendo como automatizar a construção deste template, ' \
      'então você pode olhar como está ficando para irmos validando.'
    )
  end

  it 'defines every key used by CT-01, CT-03 and CT-07 (RNF-06)' do
    keys = %w[
      subject_prefix greeting intro validation_mode data_intro not_informed service_not_informed no_documents
      closing_with_pending closing_without_pending conversation_link sign_off signature failure_note
      sections.client sections.location sections.service sections.objective sections.technical sections.other
      sections.documents sections.pending
      labels.company labels.cnpj labels.contact labels.email labels.phone labels.unit labels.address labels.city_state
      labels.location labels.area labels.depth labels.deadline labels.safety
      update.header
    ] + (1..8).map { |index| "pending_items.#{index}" }

    keys.each do |key|
      expect(I18n.exists?("scan_solo.quote.request_email.#{key}", :en)).to be(true), "missing #{key}"
      expect(I18n.t("scan_solo.quote.request_email.#{key}")).to be_a(String).and(be_present)
    end
  end

  it 'interpolates the parametrized texts' do
    scope = 'scan_solo.quote.request_email'

    expect(I18n.t("#{scope}.point", number: 2)).to eq('Ponto 2')
    expect(I18n.t("#{scope}.attachment_attached", name: 'planta.pdf', type: 'PDF')).to eq('- planta.pdf (PDF) — anexado a este e-mail.')
    expect(I18n.t("#{scope}.attachment_linked", name: 'video.mp4', type: 'vídeo', link: 'L'))
      .to eq('- video.mp4 (vídeo) — disponível na conversa: L')
    expect(I18n.t("#{scope}.update.change", label: 'Profundidade de interesse', previous: 'não informado', current: '3 m'))
      .to eq('Profundidade de interesse: não informado → 3 m')
    expect(I18n.t("#{scope}.update.new_attachment", name: 'foto.jpg', type: 'imagem')).to eq('Novo anexo: foto.jpg (imagem)')
    expect(I18n.t("#{scope}.failure_note", reason: 'Net::SMTPFatalError', link: 'L')).to include('Net::SMTPFatalError', 'L')
  end

  it 'lists the 8 CT-07 pending items in order' do
    expect((1..8).map { |index| I18n.t("scan_solo.quote.request_email.pending_items.#{index}") }).to eq(
      [
        'Área/trecho exato e dimensões a serem varridas',
        'Profundidade-alvo de investigação',
        'Necessidade e condições de integração de segurança',
        'Liberações necessárias para acesso e execução',
        'Prazo/urgência',
        'Fotos atuais do local',
        'KMZ/KML da área, se disponível',
        'Requisitos específicos de entrega'
      ]
    )
  end

  it 'leaves the OC/CT-04 block and reply instructions untouched (RF-11)' do
    expect(I18n.t('scan_solo.quote.block')).to eq(
      start: '=== RESPOSTA DO ORÇAMENTO ===',
      end: '=== FIM ===',
      labels: {
        total_value: 'Valor total', schedule: 'Prazo/cronograma', scope: 'Escopo/atividades',
        payment_terms: 'Condições de pagamento', notes: 'Observações comerciais'
      }
    )
    expect(I18n.t('scan_solo.quote.email.instructions')).to eq(
      'Responda este e-mail preenchendo o bloco abaixo, mantendo cada rótulo no início da linha. ' \
      'Valor total, prazo/cronograma, escopo/atividades e condições de pagamento são obrigatórios; ' \
      'observações comerciais são opcionais. Informe o valor no formato R$ 12.500,00.'
    )
    expect(I18n.t('scan_solo.quote.email.to_confirm')).to eq('(a confirmar)')
  end
end
