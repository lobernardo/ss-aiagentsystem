# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Quote::AmountInWords do
  {
    '12500.00' => 'doze mil e quinhentos reais',
    '1.00' => 'um real',
    '1000.00' => 'mil reais',
    '1234567.89' => 'um milhão, duzentos e trinta e quatro mil, quinhentos e sessenta e sete reais e oitenta e nove centavos',
    '0.50' => 'cinquenta centavos',
    '0.01' => 'um centavo',
    '100.00' => 'cem reais',
    '115.10' => 'cento e quinze reais e dez centavos',
    '2000000.00' => 'dois milhões de reais',
    '1500000.00' => 'um milhão e quinhentos mil reais',
    '999999999.99' => 'novecentos e noventa e nove milhões, novecentos e noventa e nove mil, novecentos e noventa e nove reais ' \
                      'e noventa e nove centavos'
  }.each do |amount, expected|
    it "writes #{amount} as \"#{expected}\" (RF-47)" do
      expect(described_class.call(BigDecimal(amount))).to eq(expected)
    end
  end

  %w[0 -1.00 1000000000.00].each do |amount|
    it "raises ArgumentError for #{amount}" do
      expect { described_class.call(BigDecimal(amount)) }.to raise_error(ArgumentError)
    end
  end
end
