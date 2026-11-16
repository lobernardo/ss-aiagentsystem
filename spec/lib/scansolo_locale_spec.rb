require 'rails_helper'

# RNF-08: backend texts of the centralized operation live in en.yml under
# `scan_solo`, not in the code.
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'ScanSolo backend locale' do
  it 'lists the 5 CT-04 labels in order' do
    expect(I18n.t('scan_solo.quote.block.labels')).to eq(
      total_value: 'Valor total',
      schedule: 'Prazo/cronograma',
      scope: 'Escopo/atividades',
      payment_terms: 'Condições de pagamento',
      notes: 'Observações comerciais'
    )
  end

  it 'delimits the CT-04 block' do
    expect(I18n.t('scan_solo.quote.block.start')).to eq('=== RESPOSTA DO ORÇAMENTO ===')
    expect(I18n.t('scan_solo.quote.block.end')).to eq('=== FIM ===')
  end

  it 'holds the RF-35 standard negotiation reply' do
    expect(I18n.t('scan_solo.negotiation.standard_reply')).to eq('Vou verificar isso com nosso comercial. Só um momento.')
  end

  it 'holds the exact RF-53 customer notice' do
    expect(I18n.t('scan_solo.quote.customer_notice')).to eq(
      'Pronto, já encaminhei para o nosso time técnico/comercial preparar o orçamento. A proposta será enviada para o e-mail informado.'
    )
  end

  it 'holds the completion reply, an intent that never claims the request was sent' do
    expect(I18n.t('scan_solo.qualification.completed_reply'))
      .to eq('Perfeito, recebi as informações. Vou encaminhar agora para o nosso time técnico/comercial preparar o orçamento.')
  end

  it 'interpolates the CT-03 quote request subject' do
    expect(I18n.t('scan_solo.quote.email.subject', opportunity_id: 42, name: 'Solar Ltda')).to eq('Solicitação de orçamento #42 — Solar Ltda')
  end

  describe 'email-first guidance (escalação filtrada RF-01/RF-02/RF-03/RF-04)' do
    let(:email) { 'comercial@example.com' }
    let(:intro) do
      'Os valores e prazos vêm na proposta que o nosso comercial envia por e-mail assim que eu concluir o seu atendimento. ' \
        'Se quiser, pode escrever para comercial@example.com.'
    end

    it 'holds the approved before_qualified text' do
      expect(I18n.t('scan_solo.commercial.email_first.before_qualified', email: email)).to eq(intro)
    end

    it 'holds the approved before_qualified_ask text with the fields' do
      expect(I18n.t('scan_solo.commercial.email_first.before_qualified_ask', email: email, fields: 'Profundidade e Prazo'))
        .to eq("#{intro} Para seguir, me informe: Profundidade e Prazo.")
    end

    it 'holds the approved quote_pending text' do
      expect(I18n.t('scan_solo.commercial.email_first.quote_pending', email: email)).to eq(
        'Seu pedido de orçamento segue para o Artur, do nosso comercial. Valores e prazos chegam na proposta por e-mail; ' \
        'se quiser, pode escrever para comercial@example.com.'
      )
    end

    it 'holds the approved quote_sent text' do
      expect(I18n.t('scan_solo.commercial.email_first.quote_sent', email: email)).to eq(
        'Seu pedido de orçamento já está com o Artur, do nosso comercial. Valores e prazos chegam na proposta, por e-mail, ' \
        'no endereço que você informou. Se quiser falar antes disso, pode escrever para comercial@example.com.'
      )
    end

    it 'requires the e-mail in every key and the fields in before_qualified_ask' do
      %w[before_qualified before_qualified_ask quote_pending quote_sent].each do |key|
        expect { I18n.t("scan_solo.commercial.email_first.#{key}", fields: 'Prazo') }.to raise_error(I18n::MissingInterpolationArgument)
      end
      expect { I18n.t('scan_solo.commercial.email_first.before_qualified_ask', email: email) }
        .to raise_error(I18n::MissingInterpolationArgument)
    end
  end

  it 'never names Luciano anywhere in the scan_solo scope (RF-08)' do
    scope = YAML.load_file(Rails.root.join('config/locales/en.yml')).dig('en', 'scan_solo')

    expect(I18n.transliterate(scope.to_json)).not_to match(/luciano/i)
  end

  it 'names the lead origins shown in the quote email' do
    expect(I18n.t('scan_solo.quote.email.origin')).to eq(website: 'Site/WhatsApp', manual: 'Comercial', none: 'Não informada')
  end
end
# rubocop:enable RSpec/DescribeClass
