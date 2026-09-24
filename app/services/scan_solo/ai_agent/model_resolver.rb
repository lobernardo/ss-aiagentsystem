# Resolves the model/provider for a ScanSolo AI Agent Center turn exclusively
# through the existing Llm::FeatureRouter (RF-21) — no second hand-rolled
# provider HTTP client, and no dependency on Enterprise code (RF-26).
class ScanSolo::AiAgent::ModelResolver
  FEATURE_KEY = 'scansolo_agent_response'.freeze

  def self.available_models
    Llm::Models.features.fetch(FEATURE_KEY).fetch('models')
  end

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
    return false if config.model_selection.nil?
    raise ArgumentError, "Unknown ScanSolo model: #{config.model_selection}" unless self.class.available_models.include?(config.model_selection)

    true
  end
end
