# Invokes the agent's resolved provider (ScanSolo::AiAgent::ModelResolver,
# RF-21) through the existing lib/llm stack (RubyLLM) with the payload built
# by ScanSolo::AiTurn::PromptBuilder: the system message as instructions, the
# history as chat messages and the structured output `{reply, actions[]}`
# (RF-05, RF-12). It measures the model call duration (`latency_ms`, RF-59)
# and bounds it with ScanSolo::AI_TURN_MODEL_TIMEOUT, which the
# per-conversation turn lock outlives (RF-11).
#
# Provider failures (timeout, API/configuration errors) return a failure
# result so the caller records the turn as failed without sending; output
# that does not follow the schema raises InvalidOutputError, and any other
# exception propagates -- ScanSolo::AiTurn::TurnOrchestrator turns every
# exception into a `failed` turn (RF-07).
#
# llm_provider is an optional injection point: production omits it (real
# invocation through lib/llm); specs inject
# ScanSolo::TestMode::MockLlmProvider (or any `call(config:, payload:)`
# object returning the same shape), so no production credential is needed.
class ScanSolo::AiTurn::ModelInvoker
  class InvalidOutputError < StandardError; end

  PROVIDER_ERRORS = [RubyLLM::Error, RubyLLM::ConfigurationError, RubyLLM::ModelNotFoundError, Timeout::Error].freeze

  Result = Struct.new(:content, :actions, :provider, :model, :input_tokens, :output_tokens, :latency_ms, :failure_reason,
                      keyword_init: true) do
    def failed?
      failure_reason.present?
    end
  end

  def self.call(config:, payload:, llm_provider: nil)
    new(config: config, payload: payload, llm_provider: llm_provider).call
  end

  def initialize(config:, payload:, llm_provider: nil)
    @config = config
    @payload = payload
    @llm_provider = llm_provider
  end

  def call
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    response = llm_provider.present? ? llm_provider.call(config: config, payload: payload) : real_response
    latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round

    build_result(response, latency_ms)
  rescue *PROVIDER_ERRORS => e
    Rails.logger.error("ScanSolo::AiTurn::ModelInvoker provider failure: #{e.class}: #{e.message}")
    Result.new(failure_reason: "#{e.class}: #{ScanSolo::AiTurn::PromptRedactor.call(e.message)}")
  end

  private

  attr_reader :config, :payload, :llm_provider

  def real_response
    Llm::Config.initialize!
    route = ScanSolo::AiAgent::ModelResolver.resolve(config: config)

    reply = build_chat(route[:model]).ask(payload[:messages].last[:content])

    route.slice(:provider, :model).merge(content: reply.content, input_tokens: reply.input_tokens, output_tokens: reply.output_tokens)
  end

  # The system message and schema frame the chat, and every history entry
  # but the last is replayed before asking with the latest one.
  def build_chat(model)
    context = RubyLLM.context do |llm_config|
      llm_config.request_timeout = ScanSolo::AI_TURN_MODEL_TIMEOUT.to_i
      llm_config.max_retries = ScanSolo::AI_TURN_MODEL_MAX_RETRIES
    end
    chat = context.chat(model: model).with_instructions(payload[:system]).with_schema(payload[:schema])
    payload[:messages][0...-1].each { |message| chat.add_message(role: message[:role].to_sym, content: message[:content]) }
    chat
  end

  def build_result(response, latency_ms)
    output = response[:content]
    unless output.is_a?(Hash) && output['reply'].is_a?(String) && output['actions'].is_a?(Array)
      raise InvalidOutputError, 'model output does not match the {reply, actions} schema'
    end

    Result.new(
      content: output['reply'], actions: output['actions'], provider: response[:provider], model: response[:model],
      input_tokens: response[:input_tokens], output_tokens: response[:output_tokens], latency_ms: latency_ms
    )
  end
end
