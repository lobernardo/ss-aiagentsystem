# CT-03 companion contract: knowledge source CRUD plus reindex (RF-27,
# RF-30, RF-31). Document uploads attach through the native ActiveStorage
# mechanism already available on ScanSolo::KnowledgeSource (RF-90); deleting
# a source cascades to its chunks (dependent: :destroy on the model),
# removing its content from future retrieval (RF-33).
class Api::V1::Accounts::ScanSolo::Knowledge::SourcesController < Api::V1::Accounts::ScanSolo::BaseController
  before_action :set_source, only: [:update, :destroy, :reindex]

  def index
    authorize(::ScanSolo::KnowledgeSource)
    @sources = ::ScanSolo::KnowledgeSource.where(account: Current.account).order(created_at: :desc)
  end

  def create
    authorize(::ScanSolo::KnowledgeSource)

    @source = ::ScanSolo::KnowledgeSource.new(source_params.merge(account: Current.account, added_by: Current.user))
    @source.file.attach(params[:file]) if params[:file].present?
    @source.save!

    ::ScanSolo::Knowledge::IngestionService.call(source: @source)

    render :show
  end

  def update
    authorize(@source)
    @source.update!(update_params)
    render :show
  end

  def destroy
    authorize(@source)
    @source.destroy!
    head :no_content
  end

  def reindex
    authorize(@source, :reindex?)
    ::ScanSolo::Knowledge::ReindexService.call(source: @source)
    render :show
  end

  private

  def set_source
    @source = ::ScanSolo::KnowledgeSource.where(account: Current.account).find(params[:id])
  end

  def source_params
    params.permit(:source_type, :title, :content, :origin)
  end

  def update_params
    params.permit(:enabled, :title, :content, :origin)
  end
end
