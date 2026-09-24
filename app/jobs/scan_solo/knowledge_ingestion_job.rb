# RF-43/RF-44: indexes one knowledge source off the request path. A source
# deleted before the job runs has nothing left to index.
class ScanSolo::KnowledgeIngestionJob < ApplicationJob
  queue_as :low

  def perform(source_id)
    source = ScanSolo::KnowledgeSource.find_by(id: source_id)
    return if source.nil?

    ScanSolo::Knowledge::IngestionService.call(source: source)
  end
end
