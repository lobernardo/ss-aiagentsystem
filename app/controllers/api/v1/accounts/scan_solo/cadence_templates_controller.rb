# CT-03: template mapping and availability per cadence stage/step and for
# the proposal send (`step: null`). Reads are open to every account user;
# writes are administrator-only (RF-48). The parameter sources, stage and
# step are validated here so a malformed mapping returns 422 before it
# reaches the upsert service.
class Api::V1::Accounts::ScanSolo::CadenceTemplatesController < Api::V1::Accounts::ScanSolo::BaseController
  def index
    authorize(::ScanSolo::TemplateMapping, :index?)
    @rows = ::ScanSolo::Messaging::TemplateAvailabilityReport.call(account: Current.account)
  end

  def update
    authorize(::ScanSolo::TemplateMapping, :update?)

    errors = mapping_errors
    return render json: { error: 'invalid_template_mapping', details: errors }, status: :unprocessable_entity if errors.any?

    ::ScanSolo::Messaging::TemplateMappingUpsertService.call(account: Current.account, actor: Current.user, attributes: mapping_attributes)
    row = ::ScanSolo::Messaging::TemplateAvailabilityReport.row(account: Current.account, stage: params[:stage], step: params[:step])
    render partial: 'api/v1/accounts/scan_solo/cadence_templates/row', locals: { row: row }
  end

  private

  def mapping_errors
    errors = []
    errors << 'stage is not a cadence stage' unless ::ScanSolo::TemplateMapping::STAGES.include?(params[:stage])
    errors << 'step does not exist for this stage' unless valid_step?
    errors << 'params must be an array' unless params[:params].is_a?(Array)
    Array(params[:params]).each do |param|
      errors << "param source #{param.try(:[], :source).inspect} is not allowed" unless allowed_param?(param)
    end
    errors
  end

  # `step: null` is the proposal send row; any other step must exist in the stage's active definition.
  def valid_step?
    step = params[:step]
    return params[:stage] == 'proposta_enviada' if step.nil?

    definition = ::ScanSolo::CadenceDefinition.current_for(params[:stage])
    step.is_a?(Integer) && definition.present? && step.between?(1, definition.attempt_count)
  end

  def allowed_param?(param)
    param.respond_to?(:key?) && ::ScanSolo::TemplateMapping::PARAM_SOURCES.include?(param[:source])
  end

  def mapping_attributes
    params.permit(:stage, :step, :template_name, :language, params: [:source, :value]).to_h.symbolize_keys
  end
end
