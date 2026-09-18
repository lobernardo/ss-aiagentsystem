# Agent test mode (RF-23): produces a simulated LLM response for a fixture
# conversation with zero calls to any real transport. WebMock
# (spec/spec_helper.rb) already blocks any non-localhost HTTP request in the
# suite, so this class deliberately never issues one — it is pure Ruby, no
# HTTP client, and requires no production LLM credential (RF-25).
class ScanSolo::TestMode::MockLlmProvider
  DEFAULT_RESPONSE = 'Resposta simulada do modo de teste do ScanSolo: nenhum envio real foi realizado.'.freeze
  PROVIDER = 'scansolo_test_mode'.freeze
  MODEL = 'scansolo-mock-llm'.freeze

  def self.call(config:, prompt:, fixture_response: nil)
    new(config: config).call(prompt: prompt, fixture_response: fixture_response)
  end

  def initialize(config:)
    @config = config
  end

  def call(prompt:, fixture_response: nil)
    content = fixture_response || DEFAULT_RESPONSE

    {
      content: content,
      provider: PROVIDER,
      model: MODEL,
      input_tokens: prompt.to_s.length,
      output_tokens: content.length,
      real_send: false
    }
  end

  private

  attr_reader :config
end
