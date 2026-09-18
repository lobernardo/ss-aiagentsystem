# Invokes the agent's resolved provider (ScanSolo::AiAgent::ModelResolver,
# RF-21) through the existing lib/llm stack (RubyLLM). On timeout/error/
# malformed output, returns a failure result instead of raising or letting
# the caller send anything (RF-42) — the caller is responsible for leaving
# already-persisted history untouched and skipping the send when
# `result.failed?`, which this class guarantees by never raising past its
# own boundary.
#
# llm_provider is an optional injection point (mirrors
# ScanSolo::Knowledge::IngestionService#embedding_provider): production
# omits it (real invocation through lib/llm); specs inject
# ScanSolo::TestMode::MockLlmProvider explicitly, matching RF-25's "no
# production credential required to exercise" guarantee for the isolated
# test suite.
class ScanSolo::AiTurn::ModelInvoker
  PROVIDER_ERRORS = [RubyLLM::Error, RubyLLM::ConfigurationError, RubyLLM::ModelNotFoundError, Timeout::Error].freeze

  Result = Struct.new(:content, :provider, :model, :input_tokens, :output_tokens, :failure_reason, keyword_init: true) do
    def failed?
      failure_reason.present?
    end
  end

  def self.call(config:, prompt:, llm_provider: nil)
    new(config: config, prompt: prompt, llm_provider: llm_provider).call
  end

  def initialize(config:, prompt:, llm_provider: nil)
    @config = config
    @prompt = prompt
    @llm_provider = llm_provider
  end

  def call
    llm_provider.present? ? mock_result : real_result
  rescue *PROVIDER_ERRORS => e
    Rails.logger.error("ScanSolo::AiTurn::ModelInvoker provider failure: #{e.class}: #{e.message}")
    Result.new(failure_reason: "#{e.class}: #{e.message}")
  end

  private

  attr_reader :config, :prompt, :llm_provider

  def mock_result
    response = llm_provider.call(config: config, prompt: prompt)

    Result.new(
      content: response[:content],
      provider: response[:provider],
      model: response[:model],
      input_tokens: response[:input_tokens],
      output_tokens: response[:output_tokens]
    )
  end

  def real_result
    Llm::Config.initialize!
    route = ScanSolo::AiAgent::ModelResolver.resolve(config: config)

    chat = RubyLLM.chat(model: route[:model])
    chat = chat.with_instructions(instructions) if instructions.present?
    reply = chat.ask(prompt)

    Result.new(
      content: reply.content,
      provider: route[:provider],
      model: route[:model],
      input_tokens: reply.input_tokens,
      output_tokens: reply.output_tokens
    )
  end

  def instructions
    [config.role, config.objective, config.persona, config.tone, config.instructions, config.service_rules]
      .select(&:present?).join("\n")
  end
end
