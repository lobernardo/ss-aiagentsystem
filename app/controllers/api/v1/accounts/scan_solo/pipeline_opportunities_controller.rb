# CT-01: pipeline stage-transition requests are idempotent per
# (opportunity_id, target_stage, actor) within a short window, implemented
# here by treating a recent matching ScanSolo::PipelineStageEvent as a replay
# instead of invoking the transition service a second time.
class Api::V1::Accounts::ScanSolo::PipelineOpportunitiesController < Api::V1::Accounts::ScanSolo::BaseController
  STAGE_TRANSITION_IDEMPOTENCY_WINDOW = 5.seconds

  before_action :set_opportunity, only: [:show, :update, :stage_transitions]

  def index
    authorize(::ScanSolo::PipelineOpportunity)
    @opportunities = ::ScanSolo::PipelineOpportunity.where(account_id: Current.account.id)
                                                    .includes(:contact, :stage_events)
  end

  def show
    authorize(@opportunity)
  end

  def update
    authorize(@opportunity)
    @opportunity.update!(update_params)
  end

  def stage_transitions
    authorize(@opportunity)

    return render :show if idempotent_replay?

    ::ScanSolo::Pipeline::StageTransitionService.new(
      opportunity: @opportunity,
      target_stage: params[:target_stage],
      actor: Current.user,
      authorized: true
    ).call

    render :show
  end

  private

  def set_opportunity
    @opportunity = ::ScanSolo::PipelineOpportunity.where(account_id: Current.account.id)
                                                  .includes(:contact, :stage_events)
                                                  .find(params[:id] || params[:pipeline_opportunity_id])
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
