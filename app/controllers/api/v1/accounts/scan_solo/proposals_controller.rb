# CT-07: `proposal.generate`/`proposal.approve`/`proposal.send`, each
# independently schema-validated (via strong params + the service layer's
# own guards), correlation-id required, version-guarded against the
# current proposal version. Read actions (index/show) exist only to feed
# UI-08's Propostas screen -- they are not part of CT-07 itself.
class Api::V1::Accounts::ScanSolo::ProposalsController < Api::V1::Accounts::ScanSolo::BaseController
  before_action :set_opportunity, only: [:generate]
  before_action :set_proposal, only: [:show, :approve, :send_proposal, :retry]

  def index
    authorize(::ScanSolo::Proposal)
    @proposals = ::ScanSolo::Proposal.joins(:opportunity)
                                     .where(scan_solo_pipeline_opportunities: { account_id: Current.account.id })
                                     .includes(:versions, opportunity: :contact)
  end

  def show
    authorize(@proposal)
  end

  def generate
    proposal = ::ScanSolo::Proposal.find_by(opportunity: @opportunity)
    authorize(proposal || ::ScanSolo::Proposal, :generate?)

    @version = ::ScanSolo::Proposal::GenerateService.call(opportunity: @opportunity, correlation_id: params.require(:correlation_id))

    render :generate
  end

  def approve
    authorize(@proposal, :approve?)

    version = @proposal.versions.find(params.require(:proposal_version_id))
    @version = ::ScanSolo::Proposal::ApproveService.call(
      proposal_version: version, correlation_id: params.require(:correlation_id), actor: Current.user
    )

    render :approve
  end

  def send_proposal
    authorize(@proposal, :send?)

    version = @proposal.versions.find(params.require(:proposal_version_id))
    @version = ::ScanSolo::Proposal::SendService.call(
      proposal_version: version, correlation_id: params.require(:correlation_id),
      conversation: @proposal.opportunity.conversation, actor: Current.user
    )

    render :send_proposal
  end

  def retry
    authorize(@proposal, :retry?)

    @version = ::ScanSolo::Proposal::RetryPolicy.retry!(
      proposal_version: @proposal.versions.where(is_current: true).find(params.require(:proposal_version_id)),
      conversation: @proposal.opportunity.conversation, actor: Current.user
    )
    render :send_proposal
  rescue ::ScanSolo::Proposal::RetryPolicy::UnsafeRetryError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def set_opportunity
    @opportunity = ::ScanSolo::PipelineOpportunity.where(account_id: Current.account.id).find(params[:pipeline_opportunity_id])
  end

  def set_proposal
    @proposal = ::ScanSolo::Proposal.joins(:opportunity)
                                    .where(scan_solo_pipeline_opportunities: { account_id: Current.account.id })
                                    .find(params[:id])
  end
end
