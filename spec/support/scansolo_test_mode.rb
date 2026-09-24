# frozen_string_literal: true

# Shared ScanSolo test-mode helpers (RF-23, RF-25): specs exercising the AI
# Agent Center's test mode build fixtures through here instead of talking to
# a real LLM provider or WhatsApp transport — WebMock (spec/spec_helper.rb)
# already blocks any non-localhost HTTP call, so an accidental real send
# fails the spec outright rather than silently succeeding.
module ScanSoloTestMode
  def scansolo_mock_llm_response(config:, payload: { messages: [] }, fixture_response: nil)
    ScanSolo::TestMode::MockLlmProvider.call(config: config, payload: payload, fixture_response: fixture_response)
  end
end

RSpec.configure do |config|
  config.include ScanSoloTestMode

  # Keeps the proposal integration state independent of a developer's local
  # config/master.key: Make credentials are absent unless a spec stubs them.
  config.before do
    allow(Rails.application.credentials).to receive(:dig).and_call_original
    allow(Rails.application.credentials).to receive(:dig).with(:scan_solo, :make, anything).and_return(nil)
  end
end
