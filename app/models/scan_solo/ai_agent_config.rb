# A live conversation only ever reads the account's draft row's
# `published_version` pointer (never the draft's own fields directly), so
# editing the draft never affects an in-progress turn until PublishService
# swaps the pointer (RF-22).
# == Schema Information
#
# Table name: scan_solo_ai_agent_configs
#
#  id                            :bigint           not null, primary key
#  enabled                       :boolean          default(FALSE), not null
#  forbidden_subjects            :jsonb            not null
#  instructions                  :text
#  model_provider                :string
#  model_selection               :string
#  name                          :string
#  objective                     :string
#  persona                       :string
#  qualification_playbook        :jsonb            not null
#  require_proposal_approval     :boolean          default(TRUE), not null
#  required_qualification_fields :jsonb            not null
#  response_limits               :text
#  restricted_information        :jsonb            not null
#  role                          :string
#  service_hours                 :string
#  service_rules                 :text
#  status                        :integer          default("draft"), not null
#  tone                          :string
#  transfer_criteria             :text
#  created_at                    :datetime         not null
#  updated_at                    :datetime         not null
#  account_id                    :bigint           not null
#  published_version_id          :bigint
#
# Indexes
#
#  index_scan_solo_ai_agent_configs_on_account_draft         (account_id) UNIQUE WHERE (status = 0)
#  index_scan_solo_ai_agent_configs_on_account_id            (account_id)
#  index_scan_solo_ai_agent_configs_on_published_version_id  (published_version_id)
#
# Foreign Keys
#
#  fk_rails_...  (published_version_id => scan_solo_ai_agent_configs.id)
#
class ScanSolo::AiAgentConfig < ApplicationRecord
  self.table_name = 'scan_solo_ai_agent_configs'

  FIELDS = %i[
    name enabled model_provider model_selection role objective persona tone
    instructions service_rules qualification_playbook required_qualification_fields
    restricted_information forbidden_subjects transfer_criteria response_limits service_hours
    require_proposal_approval
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
