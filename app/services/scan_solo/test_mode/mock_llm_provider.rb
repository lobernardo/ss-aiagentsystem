# Agent test mode (RF-23): produces a simulated LLM response for a fixture
# conversation with zero calls to any real transport. WebMock
# (spec/spec_helper.rb) already blocks any non-localhost HTTP request in the
# suite, so this class deliberately never issues one — it is pure Ruby, no
# HTTP client, and requires no production LLM credential (RF-25).
#
# It answers in the same structured shape the real provider returns
# (`content` includes reply, actions, asked_fields and summary, RF-10/CT-02) and keeps the
# last payload it received in `last_payload`, so specs can assert exactly
# what would have been sent to the provider.
class ScanSolo::TestMode::MockLlmProvider
  DEFAULT_RESPONSE = 'Resposta simulada do modo de teste do ScanSolo: nenhum envio real foi realizado.'.freeze
  PROVIDER = 'scansolo_test_mode'.freeze
  MODEL = 'scansolo-mock-llm'.freeze

  class << self
    attr_reader :last_payload
  end

  # rubocop:disable Metrics/ParameterLists
  def self.call(config:, payload:, fixture_response: nil, fixture_actions: [], fixture_asked_fields: [], fixture_summary: false)
    @last_payload = payload
    new(config: config).call(
      payload: payload, fixture_response: fixture_response, fixture_actions: fixture_actions,
      fixture_asked_fields: fixture_asked_fields, fixture_summary: fixture_summary
    )
  end

  # rubocop:enable Metrics/ParameterLists

  def initialize(config:)
    @config = config
  end

  def call(payload:, fixture_response: nil, fixture_actions: [], fixture_asked_fields: [], fixture_summary: false)
    reply = fixture_response || DEFAULT_RESPONSE

    {
      content: { 'reply' => reply, 'actions' => fixture_actions, 'asked_fields' => fixture_asked_fields, 'summary' => fixture_summary },
      provider: PROVIDER,
      model: MODEL,
      input_tokens: payload.to_json.length,
      output_tokens: reply.length,
      real_send: false
    }
  end

  private

  attr_reader :config
end
