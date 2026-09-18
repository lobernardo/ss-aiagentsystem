# CT-06: manual cadence enrollment / pause / resume / cancel. Idempotency
# key for enrollment = (opportunity_id, cadence_definition_id) (RF-59),
# enforced by ScanSolo::Cadence::EnrollmentService's unique-index-backed
# find_or_create_by!. Manual enrollment requires explicit authorization
# (RF-68), gated by ScanSolo::CadenceEnrollmentPolicy#create? before the
# service layer's own `authorized:` guard ever runs.
class Api::V1::Accounts::ScanSolo::CadenceEnrollmentsController < Api::V1::Accounts::ScanSolo::BaseController
  before_action :set_enrollment, only: [:pause, :resume, :cancel]

  def index
    authorize(::ScanSolo::CadenceEnrollment)
    @enrollments = ::ScanSolo::CadenceEnrollment.joins(:opportunity)
                                                 .where(scan_solo_pipeline_opportunities: { account_id: Current.account.id })
                                                 .where(status: %i[active paused])
                                                 .includes(:opportunity, :cadence_definition)
  end

  def create
    authorize(::ScanSolo::CadenceEnrollment)

    opportunity = ::ScanSolo::PipelineOpportunity.where(account_id: Current.account.id).find(params[:opportunity_id])
    cadence_definition = ::ScanSolo::CadenceDefinition.find(params[:cadence_definition_id])

    @enrollment = ::ScanSolo::Cadence::LifecycleService.enroll!(
      opportunity: opportunity, cadence_definition: cadence_definition, actor: Current.user, authorized: true
    )

    render :show
  end

  def pause
    authorize(@enrollment)
    @enrollment = ::ScanSolo::Cadence::LifecycleService.pause!(@enrollment)
    render :show
  end

  def resume
    authorize(@enrollment)
    @enrollment = ::ScanSolo::Cadence::LifecycleService.resume!(@enrollment)
    render :show
  end

  def cancel
    authorize(@enrollment)
    @enrollment = ::ScanSolo::Cadence::LifecycleService.cancel!(@enrollment)
    render :show
  end

  private

  def set_enrollment
    @enrollment = ::ScanSolo::CadenceEnrollment.joins(:opportunity)
                                                .where(scan_solo_pipeline_opportunities: { account_id: Current.account.id })
                                                .find(params[:id])
  end
end
