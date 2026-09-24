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
    validate_draft_params!
    ::ScanSolo::AiAgent::DraftUpdateService.call(draft: @draft, actor: Current.user, attributes: draft_params)
  end

  def publish
    authorize(@draft, :publish?)
    @published = ::ScanSolo::AiAgent::PublishService.new(account: Current.account, actor: Current.user).call
  end

  private

  def set_draft
    @draft = ::ScanSolo::AiAgentConfig.draft_for!(Current.account)
  end

  def validate_draft_params!
    if params.key?(:model_selection) && ::ScanSolo::AiAgent::ModelResolver.available_models.exclude?(params[:model_selection])
      @draft.errors.add(:model_selection, 'is not an available model')
    end

    validate_inbox_ids if params.key?(:allowed_inbox_ids)
    if params.key?(:opt_out_keywords) && !array_of?(params[:opt_out_keywords], String)
      @draft.errors.add(:opt_out_keywords, 'must be an array of strings')
    end

    raise ActiveRecord::RecordInvalid, @draft if @draft.errors.any?
  end

  def validate_inbox_ids
    ids = params[:allowed_inbox_ids]
    return if array_of?(ids, Integer) && (ids - Current.account.inboxes.where(id: ids).pluck(:id)).empty?

    @draft.errors.add(:allowed_inbox_ids, 'must contain inbox ids from this account')
  end

  def array_of?(value, type)
    value.is_a?(Array) && value.all?(type)
  end

  def draft_params
    params.permit(
      :name, :enabled, :model_provider, :model_selection, :role, :objective, :persona, :tone,
      :instructions, :service_rules, :transfer_criteria, :response_limits, :service_hours,
      :require_proposal_approval,
      allowed_inbox_ids: [],
      opt_out_keywords: [],
      qualification_playbook: [],
      required_qualification_fields: [],
      restricted_information: [],
      forbidden_subjects: []
    )
  end
end
