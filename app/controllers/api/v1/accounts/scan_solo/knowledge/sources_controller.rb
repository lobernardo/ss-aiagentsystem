# CT-02: knowledge source CRUD plus reindex (RF-27, RF-30, RF-31). Document
# uploads attach through the native ActiveStorage mechanism already
# available on ScanSolo::KnowledgeSource (RF-90); deleting a source cascades
# to its chunks (dependent: :destroy on the model), removing its content
# from future retrieval (RF-33). Indexing is asynchronous: create, a
# `content` change and reindex answer with `index_status: pending` while
# ScanSolo::KnowledgeIngestionJob rebuilds the chunks (RF-43, RF-44).
#
# Escalação comercial RF-20/CT-06: a title or content carrying the internal
# commercial contact name is rejected with 422 before anything is written.
class Api::V1::Accounts::ScanSolo::Knowledge::SourcesController < Api::V1::Accounts::ScanSolo::BaseController
  before_action :set_source, only: [:update, :destroy, :reindex]

  def index
    authorize(::ScanSolo::KnowledgeSource)
    @sources = ::ScanSolo::KnowledgeSource.where(account: Current.account).order(created_at: :desc)
  end

  def create
    authorize(::ScanSolo::KnowledgeSource)
    reject_internal_name!(::ScanSolo::KnowledgeSource.new)

    @source = ::ScanSolo::Knowledge::SourceWriteService.create!(
      account: Current.account, actor: Current.user, attributes: source_params, file: params[:file]
    )

    render :show
  end

  def update
    authorize(@source)
    reject_internal_name!(@source)
    ::ScanSolo::Knowledge::SourceWriteService.update!(source: @source, actor: Current.user, attributes: update_params)
    render :show
  end

  def destroy
    authorize(@source)
    ::ScanSolo::Knowledge::SourceWriteService.destroy!(source: @source, actor: Current.user)
    head :no_content
  end

  def reindex
    authorize(@source, :reindex?)
    ::ScanSolo::Knowledge::ReindexService.call(source: @source, actor: Current.user)
    render :show
  end

  private

  def set_source
    @source = ::ScanSolo::KnowledgeSource.where(account: Current.account).find(params[:id])
  end

  def reject_internal_name!(source)
    %i[title content].select { |attribute| ::ScanSolo::Commercial::Rules.internal_name?(params[attribute]) }.each do |attribute|
      source.errors.add(attribute, 'must not contain the internal commercial contact name')
    end
    raise ActiveRecord::RecordInvalid, source if source.errors.any?
  end

  def source_params
    params.permit(:source_type, :title, :content, :origin)
  end

  def update_params
    params.permit(:enabled, :title, :content, :origin)
  end
end
