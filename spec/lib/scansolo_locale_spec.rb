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
      'Recebi todas as informações, obrigado! Nosso comercial já está preparando seu orçamento. Assim que estiver pronto, envio por aqui.'
    )
  end

  it 'interpolates the CT-03 quote request subject' do
    expect(I18n.t('scan_solo.quote.email.subject', opportunity_id: 42, name: 'Solar Ltda')).to eq('Solicitação de orçamento #42 — Solar Ltda')
  end

  it 'names the lead origins shown in the quote email' do
    expect(I18n.t('scan_solo.quote.email.origin')).to eq(website: 'Site/WhatsApp', manual: 'Comercial', none: 'Não informada')
  end
end
# rubocop:enable RSpec/DescribeClass
