# CT-05, RF-17, RF-18, RF-21: the active proposal template of the route's
# account. The upload is checked at the boundary -- file present and at most
# MAX_BYTES before the ZIP is opened (RNF-06) -- and the `.docx` validation
# errors of ScanSolo::Proposal::TemplateDocument map to 422 `{ error:, placeholders: }`.
class Api::V1::Accounts::ScanSolo::ProposalTemplatesController < Api::V1::Accounts::ScanSolo::BaseController
  MAX_BYTES = 15 * 1024 * 1024

  rescue_from CustomExceptions::ScanSolo::ProposalTemplateInvalid do |e|
    render json: { error: e.code, placeholders: e.placeholders }.compact, status: :unprocessable_entity
  end

  def show
    authorize(::ScanSolo::ProposalTemplate)
    @template = ::ScanSolo::ProposalTemplate.active_for(Current.account)
  end

  def create
    authorize(::ScanSolo::ProposalTemplate)
    file = params[:file]
    return render_invalid('file_required') unless file.is_a?(ActionDispatch::Http::UploadedFile)
    return render_invalid('file_too_large') if file.size > MAX_BYTES

    @template = ::ScanSolo::Proposal::TemplateUploadService.call(account: Current.account, actor: Current.user, file: file)
    render :show
  end

  private

  def render_invalid(code)
    render json: { error: code }, status: :unprocessable_entity
  end
end
