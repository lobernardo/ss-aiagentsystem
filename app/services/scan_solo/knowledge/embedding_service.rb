# Resolves the knowledge-chunk embedding model exclusively through the
# existing lib/llm stack (RubyLLM + Llm::FeatureRouter), mirroring
# ScanSolo::AiAgent::ModelResolver (RF-21) — never a second hand-rolled
# provider HTTP client, and never a dependency on the enterprise-owned
# embedding service under enterprise/app/services/captain/ (RF-26).
class ScanSolo::Knowledge::EmbeddingService
  FEATURE_KEY = 'scansolo_knowledge_embedding'.freeze

  def self.call(content:, account: nil)
    new(account: account).call(content: content)
  end

  def initialize(account: nil)
    @account = account
    Llm::Config.initialize!
  end

  def call(content:)
    return [] if content.blank?

    model = Llm::FeatureRouter.resolve(feature: FEATURE_KEY, account: account)[:model]
    RubyLLM.embed(content, model: model).vectors
  end

  private

  attr_reader :account
end
