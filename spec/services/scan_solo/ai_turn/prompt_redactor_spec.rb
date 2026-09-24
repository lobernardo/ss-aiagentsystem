# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::AiTurn::PromptRedactor do
  let(:fixture_secret) { 'api-SYNTHETICREDACTIONTOKEN123456' }

  describe 'RF-88 / RNF-07: secret-shaped values never survive redaction' do
    it 'redacts a secret-shaped value from a plain string' do
      redacted = described_class.call("Authorization: Bearer #{fixture_secret}")

      expect(redacted).not_to include(fixture_secret)
      expect(redacted).to include('[REDACTED]')
    end

    it 'redacts a secret-shaped value nested inside a rendered prompt payload (hash)' do
      prompt_payload = {
        role: 'system',
        content: "Use this integration key: #{fixture_secret}",
        metadata: { nested: ["extra context with #{fixture_secret} inline"] }
      }

      redacted = described_class.call(prompt_payload)

      expect(redacted.to_s).not_to include(fixture_secret)
      expect(redacted[:content]).to include('[REDACTED]')
      expect(redacted[:metadata][:nested].first).to include('[REDACTED]')
    end

    it 'leaves ordinary prose and short identifiers untouched' do
      text = 'Ola! Seu pedido #4821 foi confirmado, obrigado pela compra.'

      expect(described_class.call(text)).to eq(text)
    end

    it 'is absent/redacted from a rendered log line produced through the app logger formatter' do
      io = StringIO.new
      logger = ActiveSupport::Logger.new(io)
      logger.formatter = Rails.logger.formatter

      logger.error("[ScanSolo::Make] outbound request used key #{fixture_secret}")

      expect(io.string).not_to include(fixture_secret)
    end
  end

  it 'preserves correlation UUIDs while redacting API keys and opaque tokens' do
    uuid = SecureRandom.uuid
    text = "correlation_id=#{uuid} key=sk-#{'x' * 40} opaque=#{'a' * 40}"

    expect(described_class.call(text)).to eq("correlation_id=#{uuid} key=[REDACTED] opaque=[REDACTED]")
  end

  it 'redacts bearer credentials even when the credential is UUID-shaped' do
    expect(described_class.call("Bearer #{SecureRandom.uuid}")).to eq('[REDACTED]')
  end
end
