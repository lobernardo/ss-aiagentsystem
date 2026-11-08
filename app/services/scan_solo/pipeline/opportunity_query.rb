# RF-12/RF-13: computes the stale indicator from the fixed
# ScanSolo::PIPELINE_STALE_THRESHOLD constant and applies Kanban/list filters
# (stage, owner, stale) at the query level.
# Relatórios RF-04/RF-10 (Q-01): the single "stalled" rule. An opportunity is
# stalled when its stage is not terminal (ganho/perdido) and
# COALESCE(last_customer_interaction_at, created_at) <= now - threshold.
# `stale?` (Ruby) and `stalled_scope` (SQL) are the only places that apply it.
class ScanSolo::Pipeline::OpportunityQuery
  TERMINAL_STAGES = ScanSolo::Pipeline::StageTransitionService::TERMINAL_STAGES
  LAST_ACTIVITY_SQL = 'COALESCE(scan_solo_pipeline_opportunities.last_customer_interaction_at, ' \
                      'scan_solo_pipeline_opportunities.created_at)'.freeze

  def self.stale?(opportunity, now: Time.current)
    return false if TERMINAL_STAGES.include?(opportunity.stage)

    (opportunity.last_customer_interaction_at || opportunity.created_at) <= now - ScanSolo::PIPELINE_STALE_THRESHOLD
  end

  def self.stalled_scope(scope, as_of:)
    scope.where.not(stage: TERMINAL_STAGES)
         .where("#{LAST_ACTIVITY_SQL} <= ?", as_of - ScanSolo::PIPELINE_STALE_THRESHOLD)
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
    stalled = self.class.stalled_scope(ScanSolo::PipelineOpportunity.all, as_of: Time.current)

    if ActiveModel::Type::Boolean.new.cast(stale)
      scope.merge(stalled)
    else
      scope.where.not(id: stalled.select(:id))
    end
  end
end
