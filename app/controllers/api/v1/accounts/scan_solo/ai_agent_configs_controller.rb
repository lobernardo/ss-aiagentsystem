# CT-02: draft vs published configuration are exposed distinctly, and
# publish is an explicit, atomic operation (RF-22) — the draft is never
# mutated by #publish, only read from.
class Api::V1::Accounts::ScanSolo::AiAgentConfigsController < Api::V1::Accounts::ScanSolo::BaseController
  before_action :set_draft

  def show
    authorize(@draft)
    @published = @draft.published_version
  end

  def draft
    authorize(@draft)
    @draft.update!(draft_params)
  end

  def publish
    authorize(@draft, :publish?)
    @published = ::ScanSolo::AiAgent::PublishService.new(account: Current.account).call
  end

  private

  def set_draft
    @draft = ::ScanSolo::AiAgentConfig.draft_for!(Current.account)
  end

  def draft_params
    params.permit(
      :name, :enabled, :model_provider, :model_selection, :role, :objective, :persona, :tone,
      :instructions, :service_rules, :transfer_criteria, :response_limits, :service_hours,
      :require_proposal_approval,
      qualification_playbook: [],
      required_qualification_fields: [],
      restricted_information: [],
      forbidden_subjects: []
    )
  end
end
