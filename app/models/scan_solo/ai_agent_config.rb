# A live conversation only ever reads the account's draft row's
# `published_version` pointer (never the draft's own fields directly), so
# editing the draft never affects an in-progress turn until PublishService
# swaps the pointer (RF-22).
class ScanSolo::AiAgentConfig < ApplicationRecord
  self.table_name = 'scan_solo_ai_agent_configs'

  FIELDS = %i[
    name enabled model_provider model_selection role objective persona tone
    instructions service_rules qualification_playbook required_qualification_fields
    restricted_information forbidden_subjects transfer_criteria response_limits service_hours
  ].freeze

  belongs_to :account
  belongs_to :published_version, class_name: 'ScanSolo::AiAgentConfig', optional: true

  enum status: { draft: 0, published: 1 }

  validates :account_id, uniqueness: { scope: :status }, if: -> { draft? }

  def self.draft_for!(account)
    find_or_create_by!(account: account, status: :draft)
  end

  def self.published_for(account)
    draft_for!(account).published_version
  end
end
