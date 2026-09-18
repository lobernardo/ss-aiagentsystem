# CT-03: operator-submitted retrieval simulator query, outside a live
# conversation (RF-32). Returns ranked chunks with source/evidence ids
# (RF-29). A vector-store outage never raises here — RetrievalService
# already degrades to an empty result set plus a failure reason (RF-34).
class Api::V1::Accounts::ScanSolo::Knowledge::RetrievalTestsController < Api::V1::Accounts::ScanSolo::BaseController
  DEFAULT_TOP_K = ::ScanSolo::Knowledge::RetrievalService::DEFAULT_TOP_K

  def create
    authorize(::ScanSolo::KnowledgeSource, :retrieval_tests?)

    if params[:query].blank?
      render json: { errors: ['query is required'] }, status: :unprocessable_entity
      return
    end

    @response = ::ScanSolo::Knowledge::RetrievalService.call(
      account: Current.account,
      query: params[:query],
      top_k: top_k_param
    )
  end

  private

  def top_k_param
    params[:top_k].presence&.to_i || DEFAULT_TOP_K
  end
end
