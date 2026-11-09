# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Commercial::Rules do
  describe '.internal_name?' do
    it 'matches the internal name ignoring case and accents' do
      %w[luciano LUCIANO Lucíano].each do |text|
        expect(described_class.internal_name?(text)).to be(true), "expected #{text} to match"
      end
    end

    it 'matches the internal name inside a longer text' do
      expect(described_class.internal_name?('fale com o Luciano amanhã')).to be true
    end

    it 'does not match other names or a partial name' do
      %w[Artur Luci].each do |text|
        expect(described_class.internal_name?(text)).to be(false), "expected #{text} not to match"
      end
    end

    it 'treats nil as no match' do
      expect(described_class.internal_name?(nil)).to be false
    end
  end

  describe 'E164_PHONE_REGEXP' do
    it 'accepts an E.164 number' do
      phone = '+5511999999999'

      expect(phone).to match(described_class::E164_PHONE_REGEXP)
    end

    it 'rejects a number without the plus/country code or with separators' do
      ['11999999999', '+55 11 99999-9999'].each do |phone|
        expect(phone).not_to match(described_class::E164_PHONE_REGEXP)
      end
    end
  end
end
