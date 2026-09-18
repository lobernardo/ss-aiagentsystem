# Resolves the model/provider for a ScanSolo AI Agent Center turn exclusively
# through the existing Llm::FeatureRouter (RF-21) — no second hand-rolled
# provider HTTP client, and no dependency on enterprise/ Captain code (RF-26).
class ScanSolo::AiAgent::ModelResolver
  FEATURE_KEY = 'scansolo_agent_response'.freeze

  def self.resolve(config:)
    new(config: config).resolve
  end

  def initialize(config:)
    @config = config
  end

  def resolve
    route = Llm::FeatureRouter.resolve(feature: FEATURE_KEY, account: config.account)
    return route unless configured_model_override?

    route.merge(
      provider: Llm::Models.provider_for(config.model_selection),
      model: config.model_selection,
      source: :agent_config
    )
  end

  private

  attr_reader :config

  def configured_model_override?
    config.model_selection.present? && Llm::Models.valid_model_for?(FEATURE_KEY, config.model_selection)
  end
end
