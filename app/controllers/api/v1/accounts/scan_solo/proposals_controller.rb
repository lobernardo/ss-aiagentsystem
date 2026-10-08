# CT-07: `proposal.generate`/`proposal.approve`/`proposal.send`, each
# independently schema-validated (via strong params + the service layer's
# own guards), correlation-id required, version-guarded against the
# current proposal version. Read actions (index/show) exist only to feed
# UI-08's Propostas screen -- they are not part of CT-07 itself.
#
# CT-02/CT-03 (RF-04, RF-05, RF-08): approve and reject act on the current
# `awaiting_approval` version; the boundary refuses an approval while the
# lead has no valid e-mail (`lead_email_missing`) and a rejection without a
# reason (`reason_required`). Service refusals map to 422 `{ error: code }`.
class Api::V1::Accounts::ScanSolo::ProposalsController < Api::V1::Accounts::ScanSolo::BaseController
  before_action :set_opportunity, only: [:generate]
  before_action :set_proposal, only: [:approve, :reject, :send_proposal, :retry]

  rescue_from CustomExceptions::ScanSolo::ProposalActionRejected do |e|
    render json: { error: e.code }, status: :unprocessable_entity
  end

  # CT-01: everything the version/proposal partials read, loaded up front.
  READ_PRELOAD = {
    versions: [:approved_by, :rejected_by, { sent_message: :inbox }, :notice_message, { document_attachment: :blob }],
    opportunity: %i[contact quote_request]
  }.freeze

  def index
    authorize(::ScanSolo::Proposal)
    @proposals = account_proposals.includes(READ_PRELOAD)
  end

  def show
    @proposal = account_proposals.includes(READ_PRELOAD).find(params[:id])
    authorize(@proposal)
  end

  def generate
    proposal = ::ScanSolo::Proposal.find_by(opportunity: @opportunity)
    authorize(proposal || ::ScanSolo::Proposal, :generate?)

    @version = ::ScanSolo::Proposal::GenerateService.call(
      opportunity: @opportunity, quote_request: @opportunity.quote_request, correlation_id: params.require(:correlation_id), actor: Current.user
    )

    render :generate
  end

  def approve
    authorize(@proposal, :approve?)

    version = @proposal.versions.find(params.require(:proposal_version_id))
    params.require(:correlation_id)
    if version.awaiting_approval? && !@proposal.opportunity.lead_email_valid?
      return render json: { error: 'lead_email_missing' }, status: :unprocessable_entity
    end

    @version = ::ScanSolo::Proposal::ApproveService.call(proposal_version: version, actor: Current.user)

    render :approve
  end

  def reject
    authorize(@proposal, :reject?)

    version = @proposal.versions.find(params.require(:proposal_version_id))
    return render json: { error: 'reason_required' }, status: :unprocessable_entity if params[:reason].to_s.strip.blank?

    @version = ::ScanSolo::Proposal::RejectService.call(proposal_version: version, actor: Current.user, reason: params[:reason].to_s)

    render :reject
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
    params.require(:proposal_version_id)
    # CT-04: `confirm_reprocess` is a required boolean.
    unless [true, false].include?(params[:confirm_reprocess])
      return render json: { error: 'confirm_reprocess must be a boolean' }, status: :unprocessable_entity
    end

    @version = ::ScanSolo::Proposal::RetryPolicy.retry!(
      proposal_version: @proposal.versions.where(is_current: true).find(params[:proposal_version_id]),
      confirm_reprocess: params[:confirm_reprocess], actor: Current.user
    )
    render :retry
  rescue ::ScanSolo::Proposal::RetryPolicy::UnsafeRetryError, ::ScanSolo::Proposal::RetryPolicy::ReprocessConfirmationRequiredError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def set_opportunity
    @opportunity = ::ScanSolo::PipelineOpportunity.where(account_id: Current.account.id).find(params[:pipeline_opportunity_id])
  end

  def set_proposal
    @proposal = account_proposals.find(params[:id])
  end

  def account_proposals
    ::ScanSolo::Proposal.joins(:opportunity).where(scan_solo_pipeline_opportunities: { account_id: Current.account.id })
  end
end
