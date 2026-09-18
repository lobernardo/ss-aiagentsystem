# Sole call path for publishing a ScanSolo::AiAgentConfig draft (RF-22): the
# published snapshot is an immutable new row, and the draft's pointer to it
# is swapped in the same transaction so no interleaved read ever sees a
# half-published config.
class ScanSolo::AiAgent::PublishService
  def initialize(account:)
    @account = account
  end

  def call
    draft = ScanSolo::AiAgentConfig.draft_for!(account)

    ActiveRecord::Base.transaction do
      snapshot = ScanSolo::AiAgentConfig.create!(
        snapshot_attributes(draft).merge(account: account, status: :published)
      )
      draft.update!(published_version: snapshot)
    end

    draft.reload.published_version
  end

  private

  attr_reader :account

  def snapshot_attributes(draft)
    draft.attributes.symbolize_keys.slice(*ScanSolo::AiAgentConfig::FIELDS)
  end
end
