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
class Api::V1::Accounts::ScanSolo::PipelineOpportunitiesController < Api::V1::Accounts::ScanSolo::BaseController
  STAGE_TRANSITION_IDEMPOTENCY_WINDOW = 5.seconds

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

  def update
    authorize(@opportunity)
    @opportunity.update!(update_params)
    project_lead_state
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
    params.permit(:owner_id)
  end

  def idempotent_replay?
    target_stage = params[:target_stage].to_s

    return false unless @opportunity.stage == target_stage

    @opportunity.stage_events
                .where(to_stage: target_stage, actor: Current.user)
                .exists?(['created_at >= ?', STAGE_TRANSITION_IDEMPOTENCY_WINDOW.ago])
  end
end
