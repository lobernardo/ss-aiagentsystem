# frozen_string_literal: true

# RF-91 / RNF-03 defense-in-depth for the ScanSolo isolated test-mode suite:
# spec/spec_helper.rb already calls WebMock.disable_net_connect!(allow_localhost:
# true) for the whole test run, so any unstubbed HTTP call already raises. This
# file adds an explicit, ScanSolo-scoped assertion of that guarantee (so a
# future weakening of the global setting fails loudly for this suite instead of
# silently passing) plus shared helpers the full isolated test-mode integration
# suite (spec/integration/scan_solo/full_test_mode_spec.rb) uses to prove, in
# the suite itself, that zero real outbound requests were made and zero
# production credential is required.
module ScanSoloWebmockEnforcement
  PRODUCTION_CREDENTIAL_ENV_KEYS = %w[
    OPENAI_API_KEY
    AZURE_OPENAI_API_KEY
    GOOGLE_API_KEY
    ANTHROPIC_API_KEY
    WHATSAPP_CLOUD_API_TOKEN
    WHATSAPP_API_KEY
    MAKE_WEBHOOK_SECRET
  ].freeze

  PRODUCTION_HOST_PATTERNS = [
    /graph\.facebook\.com/,
    /waba\.360dialog\.io/,
    /hooks?\.[a-z0-9.-]*make\.com/,
    /api\.openai\.com/,
    /api\.anthropic\.com/
  ].freeze

  def scansolo_assert_no_production_credentials_present!
    ScanSoloWebmockEnforcement::PRODUCTION_CREDENTIAL_ENV_KEYS.each do |key|
      expect(ENV.fetch(key, nil)).to(
        be_nil, "expected production credential #{key} to be absent for the ScanSolo isolated test-mode suite (RNF-03)"
      )
    end
  end

  def scansolo_assert_zero_real_outbound_requests!
    ScanSoloWebmockEnforcement::PRODUCTION_HOST_PATTERNS.each do |pattern|
      expect(a_request(:any, pattern)).not_to have_been_made
    end
  end
end

RSpec.configure do |config|
  config.include ScanSoloWebmockEnforcement

  config.before(:each, :scansolo_full_test_mode) do
    raise 'WebMock net connect must be disabled for the ScanSolo isolated test-mode suite (RF-91)' if WebMock.net_connect_allowed?
  end
end
