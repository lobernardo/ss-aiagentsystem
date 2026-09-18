# RF-78: per-account toggle for whether `proposal.send` requires an explicit
# recorded approval before executing. Defaults to true (the safer
# fail-closed default) so a freshly-seeded account requires approval until
# an administrator explicitly turns it off.
class AddRequireProposalApprovalToScanSoloAiAgentConfigs < ActiveRecord::Migration[7.1]
  def change
    add_column :scan_solo_ai_agent_configs, :require_proposal_approval, :boolean, null: false, default: true
  end
end
