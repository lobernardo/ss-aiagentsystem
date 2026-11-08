# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Reports::Period do
  around do |example|
    Time.use_zone('UTC') { example.run }
  end

  describe 'week (RF-07)' do
    subject(:period) { described_class.resolve(period: 'week', anchor: Date.new(2026, 11, 8)) }

    it 'runs from Monday 00:00 to the next Monday 00:00 in America/Sao_Paulo' do
      expect(period.starts_at.iso8601).to eq('2026-11-02T00:00:00-03:00')
      expect(period.ends_at.iso8601).to eq('2026-11-09T00:00:00-03:00')
      expect(period.period).to eq('week')
      expect(period.anchor).to eq(Date.new(2026, 11, 8))
    end

    it 'keeps Sunday 23:59:59 SP inside and Monday 00:00 SP outside (RNF-07)' do
      expect(period.range).to cover(Time.utc(2026, 11, 9, 2, 59, 59))
      expect(period.range).not_to cover(Time.utc(2026, 11, 9, 3, 0, 0))
      expect(period.range).to cover(Time.utc(2026, 11, 2, 3, 0, 0))
      expect(period.range).not_to cover(Time.utc(2026, 11, 2, 2, 59, 59))
    end

    it 'resolves the same week for a Monday anchor' do
      monday = described_class.resolve(period: 'week', anchor: Date.new(2026, 11, 2))

      expect(monday.starts_at).to eq(period.starts_at)
      expect(monday.ends_at).to eq(period.ends_at)
    end

    it 'has the immediately preceding week as previous (RF-09)' do
      previous = period.previous

      expect(previous.period).to eq('week')
      expect(previous.starts_at.iso8601).to eq('2026-10-26T00:00:00-03:00')
      expect(previous.ends_at).to eq(period.starts_at)
    end

    it 'is closed only once ends_at has passed' do
      expect(period.closed?(Time.utc(2026, 11, 9, 2, 59, 59))).to be(false)
      expect(period.closed?(Time.utc(2026, 11, 9, 3, 0, 0))).to be(true)
    end
  end

  describe 'month (RF-07)' do
    it 'runs from day 1 00:00 to the first day of the next month in SP' do
      period = described_class.resolve(period: 'month', anchor: Date.new(2026, 2, 14))

      expect(period.starts_at.iso8601).to eq('2026-02-01T00:00:00-03:00')
      expect(period.ends_at.iso8601).to eq('2026-03-01T00:00:00-03:00')
      expect(period.range).to cover(Time.utc(2026, 3, 1, 2, 59, 59))
      expect(period.range).not_to cover(Time.utc(2026, 3, 1, 3, 0, 0))
    end

    it 'has the immediately preceding month as previous, across the year (RF-09)' do
      previous = described_class.resolve(period: 'month', anchor: Date.new(2026, 1, 31)).previous

      expect(previous.period).to eq('month')
      expect(previous.starts_at.iso8601).to eq('2025-12-01T00:00:00-03:00')
      expect(previous.ends_at.iso8601).to eq('2026-01-01T00:00:00-03:00')
    end
  end

  it 'exposes the timezone and the accepted periods' do
    expect(described_class::TIMEZONE).to eq('America/Sao_Paulo')
    expect(described_class::PERIODS).to eq(%w[week month])
  end
end
