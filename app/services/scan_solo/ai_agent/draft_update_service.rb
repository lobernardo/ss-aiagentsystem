# RF-50: the sole writer of the agent config draft. Applies the validated
# attributes and records one `ai_agent_config.draft_updated` audit event
# listing the changed field names (never their values) and whether the
# opt-out keyword list changed (RF-16).
class ScanSolo::AiAgent::DraftUpdateService
  def self.call(draft:, actor:, attributes:)
    new(draft: draft, actor: actor, attributes: attributes).call
  end

  def initialize(draft:, actor:, attributes:)
    @draft = draft
    @actor = actor
    @attributes = attributes
  end

  def call
    ActiveRecord::Base.transaction do
      draft.update!(attributes)
      changed_fields = draft.saved_changes.keys - %w[updated_at]
      ScanSolo::AuditLogger.record!(
        subject: draft, event_type: 'ai_agent_config.draft_updated', actor: actor, correlation_id: SecureRandom.uuid,
        payload: { changed_fields: changed_fields, opt_out_keywords_changed: changed_fields.include?('opt_out_keywords') }
      )
    end

    draft
  end

  private

  attr_reader :draft, :actor, :attributes
end
