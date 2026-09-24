# CT-03: operator-submitted retrieval simulator query, outside a live
# conversation (RF-32). Returns ranked chunks with source/evidence ids
# (RF-29). A vector-store outage never raises here — RetrievalService
# already degrades to an empty result set plus a failure reason (RF-34).
#
# RNF-06: `top_k` is capped at MAX_TOP_K at the request boundary.
class Api::V1::Accounts::ScanSolo::Knowledge::RetrievalTestsController < Api::V1::Accounts::ScanSolo::BaseController
  DEFAULT_TOP_K = ::ScanSolo::Knowledge::RetrievalService::DEFAULT_TOP_K
  MAX_TOP_K = 20

  def create
    authorize(::ScanSolo::KnowledgeSource, :retrieval_tests?)

    errors = request_errors
    return render json: { errors: errors }, status: :unprocessable_entity if errors.any?

    @response = ::ScanSolo::Knowledge::RetrievalService.call(
      account: Current.account,
      query: params[:query],
      top_k: top_k_param
    )
  end

  private

  def request_errors
    errors = []
    errors << 'query is required' if params[:query].blank?
    if params.key?(:top_k) && !(params[:top_k].is_a?(Integer) && params[:top_k].between?(1, MAX_TOP_K))
      errors << "top_k must be an integer between 1 and #{MAX_TOP_K}"
    end
    errors
  end

  def top_k_param
    params[:top_k] || DEFAULT_TOP_K
  end
end
