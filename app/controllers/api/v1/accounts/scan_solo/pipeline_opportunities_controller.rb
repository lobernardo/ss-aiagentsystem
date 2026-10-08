# CT-01: pipeline stage-transition requests are idempotent per
# (opportunity_id, target_stage, actor) within a short window, implemented
# here by treating a recent matching ScanSolo::PipelineStageEvent as a replay
# instead of invoking the transition service a second time.
#
# CT-01 / RF-26: show, update and stage_transitions (replay included) also
# render the opportunity's `lead_state` projection; index does not.
#
# CT-02 / RNF-06: index preloads everything its items render and groups the
# next follow-up of the whole list in one query, so its query count does not
# grow with the number of opportunities.
#
# CT-01 / RF-05: create ("Novo lead") rejects malformed input here with 422
# before any write; the database rules (opt-out, conflict, open opportunity)
# belong to ScanSolo::Pipeline::ManualLeadService.
#
# CT-09 / RF-09: update also edits the lead e-mail; a malformed or empty
# address is refused here with 422 `invalid_email`, the conflict with another
# contact belongs to ScanSolo::Pipeline::LeadEmailService.
class Api::V1::Accounts::ScanSolo::PipelineOpportunitiesController < Api::V1::Accounts::ScanSolo::BaseController
  STAGE_TRANSITION_IDEMPOTENCY_WINDOW = 5.seconds
  E164_PHONE_REGEXP = /\A\+[1-9]\d{1,14}\z/

  before_action :set_opportunity, only: [:show, :update, :stage_transitions]

  def index
    authorize(::ScanSolo::PipelineOpportunity)
    @opportunities = ::ScanSolo::PipelineOpportunity.where(account_id: Current.account.id)
                                                    .includes(:contact, :stage_events, :lead_state, :quote_request, :conversation_extension,
                                                              proposal: :current_version)
    @next_follow_ups = ::ScanSolo::CadenceEnrollment.active.where(opportunity_id: @opportunities.map(&:id))
                                                    .group(:opportunity_id).minimum(:next_attempt_at)
  end

  def show
    authorize(@opportunity)
    project_lead_state
  end

  def create
    authorize(::ScanSolo::PipelineOpportunity)
    error = manual_lead_input_error
    return render(json: { error: error }, status: :unprocessable_entity) if error

    result = ::ScanSolo::Pipeline::ManualLeadService.call(account: Current.account, actor: Current.user, inbox: manual_lead_inbox,
                                                          **manual_lead_attributes)
    @opportunity = result.opportunity
    @contact_created = result.contact_created
    project_lead_state
    render :create, status: :created
  rescue CustomExceptions::ScanSolo::ManualLeadRejected => e
    render json: { error: e.code, opportunity_id: e.opportunity_id }.compact, status: :unprocessable_entity
  end

  def update
    authorize(@opportunity)
    input = update_params
    if input.key?(:email)
      return render(json: { error: 'invalid_email' }, status: :unprocessable_entity) unless input[:email].to_s.match?(URI::MailTo::EMAIL_REGEXP)

      ::ScanSolo::Pipeline::LeadEmailService.call(opportunity: @opportunity, email: input[:email])
    end
    @opportunity.update!(input.except(:email))
    project_lead_state
  rescue CustomExceptions::ScanSolo::LeadEmailRejected => e
    render json: { error: e.code }, status: :unprocessable_entity
  end

  def stage_transitions
    authorize(@opportunity)

    unless idempotent_replay?
      ::ScanSolo::Pipeline::StageTransitionService.new(
        opportunity: @opportunity,
        target_stage: params[:target_stage],
        actor: Current.user,
        authorized: true
      ).call
      @opportunity.stage_events.reset
    end

    project_lead_state
    render :show
  end

  private

  def set_opportunity
    @opportunity = ::ScanSolo::PipelineOpportunity.where(account_id: Current.account.id)
                                                  .includes(:contact, :stage_events, :quote_request, :conversation_extension,
                                                            lead_state: :events, proposal: { current_version: { document_attachment: :blob } })
                                                  .find(params[:id] || params[:pipeline_opportunity_id])
  end

  def project_lead_state
    @lead_state = ::ScanSolo::LeadState::Projection.call(opportunity: @opportunity,
                                                         config: ::ScanSolo::AiAgentConfig.published_for(Current.account))
  end

  def update_params
    params.permit(:owner_id, :email)
  end

  def create_params
    params.permit(:name, :phone_number, :email, :company, :owner_id, :inbox_id)
  end

  def manual_lead_attributes
    input = create_params
    { name: input[:name], phone_number: input[:phone_number], email: input[:email].presence, company: input[:company].presence,
      owner_id: input[:owner_id].presence }
  end

  def manual_lead_input_error
    input = create_params
    return 'missing_name' if input[:name].blank?
    return 'invalid_phone' unless input[:phone_number].to_s.match?(E164_PHONE_REGEXP)
    return 'invalid_email' if input[:email].present? && !input[:email].match?(URI::MailTo::EMAIL_REGEXP)

    manual_lead_reference_error
  end

  def manual_lead_reference_error
    return 'invalid_owner' if create_params[:owner_id].present? && !Current.account.users.exists?(id: create_params[:owner_id])

    'invalid_inbox' if manual_lead_inbox.blank?
  end

  # UI-01: a WhatsApp inbox of the published allowlist; `inbox_id` may be
  # omitted only when exactly one such inbox exists.
  def manual_lead_inbox
    @manual_lead_inbox ||= begin
      allowlisted = Current.account.inboxes.where(id: ::ScanSolo::AiAgentConfig.published_for(Current.account)&.allowed_inbox_ids.to_a,
                                                  channel_type: 'Channel::Whatsapp')
      if create_params[:inbox_id].present?
        allowlisted.find_by(id: create_params[:inbox_id])
      else
        candidates = allowlisted.limit(2).to_a
        candidates.first if candidates.one?
      end
    end
  end

  def idempotent_replay?
    target_stage = params[:target_stage].to_s

    return false unless @opportunity.stage == target_stage

    @opportunity.stage_events
                .where(to_stage: target_stage, actor: Current.user)
                .exists?(['created_at >= ?', STAGE_TRANSITION_IDEMPOTENCY_WINDOW.ago])
  end
end
