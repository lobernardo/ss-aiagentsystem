# Sole call path for publishing a ScanSolo::AiAgentConfig draft (RF-22): the
# published snapshot is an immutable new row, and the draft's pointer to it
# is swapped in the same transaction so no interleaved read ever sees a
# half-published config. Records one `ai_agent_config.published` audit
# event (RF-50) in that same transaction.
class ScanSolo::AiAgent::PublishService
  def initialize(account:, actor: nil)
    @account = account
    @actor = actor
  end

  def call
    draft = ScanSolo::AiAgentConfig.draft_for!(account)

    ActiveRecord::Base.transaction do
      snapshot = ScanSolo::AiAgentConfig.create!(
        snapshot_attributes(draft).merge(account: account, status: :published)
      )
      draft.update!(published_version: snapshot)
      ScanSolo::AuditLogger.record!(
        subject: snapshot, event_type: 'ai_agent_config.published', actor: actor, correlation_id: SecureRandom.uuid,
        payload: { draft_id: draft.id, published_config_id: snapshot.id }
      )
    end

    draft.reload.published_version
  end

  private

  attr_reader :account, :actor

  def snapshot_attributes(draft)
    draft.attributes.symbolize_keys.slice(*ScanSolo::AiAgentConfig::FIELDS)
  end
end
