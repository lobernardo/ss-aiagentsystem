# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::OptOut::KeywordMatcher do
  let(:keywords) { %w[PARAR SAIR STOP] }

  describe '.match? (RF-16 (b))' do
    ['Parar!', '  sair ', 'stop.', 'PÁRAR'].each do |content|
      it "matches #{content.inspect} against the default keywords" do
        expect(described_class.match?(content, keywords)).to be true
      end
    end

    ['não vou parar agora', 'parar de receber?', '', nil].each do |content|
      it "does not match #{content.inspect}" do
        expect(described_class.match?(content, keywords)).to be false
      end
    end

    it 'normalizes the configured keywords too' do
      expect(described_class.match?('nao quero', ['Não quero!'])).to be true
    end

    it 'never matches with an empty keyword list' do
      expect(described_class.match?('PARAR', [])).to be false
    end
  end
end
