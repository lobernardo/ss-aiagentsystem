# CT-02: draft vs published configuration are exposed distinctly, and
# publish is an explicit, atomic operation (RF-22) — the draft is never
# mutated by #publish, only read from.
#
# RF-54: the quote inbox, commercial user and commercial recipient are part
# of the publish snapshot. RF-14/RF-16: the quote inbox must be an email inbox
# of the account kept outside the effective allowlist, rejected here (422).
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
    validate_agent_params
    validate_commercial_params
    raise ActiveRecord::RecordInvalid, @draft if @draft.errors.any?
  end

  def validate_agent_params
    if params.key?(:model_selection) && ::ScanSolo::AiAgent::ModelResolver.available_models.exclude?(params[:model_selection])
      @draft.errors.add(:model_selection, 'is not an available model')
    end

    validate_inbox_ids if params.key?(:allowed_inbox_ids)
    return unless params.key?(:opt_out_keywords) && !array_of?(params[:opt_out_keywords], String)

    @draft.errors.add(:opt_out_keywords, 'must be an array of strings')
  end

  def validate_commercial_params
    validate_quote_inbox if params.key?(:quote_inbox_id) || params.key?(:allowed_inbox_ids)
    validate_commercial_user if params.key?(:commercial_user_id)
    validate_quote_recipient_email if params.key?(:quote_recipient_email)
  end

  def validate_inbox_ids
    ids = params[:allowed_inbox_ids]
    return if array_of?(ids, Integer) && (ids - Current.account.inboxes.where(id: ids).pluck(:id)).empty?

    @draft.errors.add(:allowed_inbox_ids, 'must contain inbox ids from this account')
  end

  def validate_quote_inbox
    quote_inbox_id = params.fetch(:quote_inbox_id, @draft.quote_inbox_id)
    return if quote_inbox_id.nil?

    if params.key?(:quote_inbox_id) && !email_inbox_id?(quote_inbox_id)
      @draft.errors.add(:quote_inbox_id, 'must be an email inbox from this account')
    elsif Array(params.fetch(:allowed_inbox_ids, @draft.allowed_inbox_ids)).include?(quote_inbox_id)
      @draft.errors.add(:quote_inbox_id, 'must not be in allowed_inbox_ids')
    end
  end

  def email_inbox_id?(inbox_id)
    inbox_id.is_a?(Integer) && Current.account.inboxes.exists?(id: inbox_id, channel_type: 'Channel::Email')
  end

  def validate_commercial_user
    user_id = params[:commercial_user_id]
    return if user_id.nil? || (user_id.is_a?(Integer) && Current.account.users.exists?(id: user_id))

    @draft.errors.add(:commercial_user_id, 'must be a user from this account')
  end

  def validate_quote_recipient_email
    email = params[:quote_recipient_email]
    return if email.is_a?(String) && email.match?(URI::MailTo::EMAIL_REGEXP)

    @draft.errors.add(:quote_recipient_email, 'must be a valid email address')
  end

  def array_of?(value, type)
    value.is_a?(Array) && value.all?(type)
  end

  def draft_params
    params.permit(
      :name, :enabled, :model_provider, :model_selection, :role, :objective, :persona, :tone,
      :instructions, :service_rules, :transfer_criteria, :response_limits, :service_hours,
      :require_proposal_approval, :quote_inbox_id, :commercial_user_id, :quote_recipient_email,
      allowed_inbox_ids: [],
      opt_out_keywords: [],
      qualification_playbook: [],
      required_qualification_fields: [],
      restricted_information: [],
      forbidden_subjects: []
    )
  end
end
