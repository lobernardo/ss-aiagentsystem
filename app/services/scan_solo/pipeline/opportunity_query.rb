# RF-12/RF-13: computes the stale indicator from the fixed
# ScanSolo::PIPELINE_STALE_THRESHOLD constant and applies Kanban/list filters
# (stage, owner, stale) at the query level.
class ScanSolo::Pipeline::OpportunityQuery
  def self.stale?(opportunity)
    last_interaction = opportunity.last_customer_interaction_at
    return false if last_interaction.blank?

    last_interaction <= ScanSolo::PIPELINE_STALE_THRESHOLD.ago
  end

  def initialize(scope: ScanSolo::PipelineOpportunity.all, stage: nil, owner_id: nil, stale: nil)
    @scope = scope
    @stage = stage
    @owner_id = owner_id
    @stale = stale
  end

  def results
    scope = @scope
    scope = scope.where(stage: @stage) if @stage.present?
    scope = scope.where(owner_id: @owner_id) if @owner_id.present?
    scope = filter_by_stale(scope) unless @stale.nil?
    scope
  end

  private

  attr_reader :stale

  def filter_by_stale(scope)
    threshold = ScanSolo::PIPELINE_STALE_THRESHOLD.ago
    column = ScanSolo::PipelineOpportunity.arel_table[:last_customer_interaction_at]

    if ActiveModel::Type::Boolean.new.cast(stale)
      scope.where(column.lteq(threshold))
    else
      scope.where(column.gt(threshold).or(column.eq(nil)))
    end
  end
end
