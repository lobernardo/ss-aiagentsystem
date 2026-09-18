# RF-56/RF-66: the single service every stop/recalculate trigger routes
# through, so there is exactly one implementation of "stop pending cadence
# work for this opportunity" rather than one per caller (avoiding policy
# drift between the six RF-66 triggers and RF-56's human-takeover case).
# Delegates entirely to ScanSolo::Cadence::LifecycleService (T51), which
# already guarantees an already-sent attempt is never retroactively
# altered -- only `scheduled` rows are ever touched.
#
# Wired in from:
# - ScanSolo::Pipeline::StageTransitionService (T12) for stage_changed/won/lost
# - ScanSolo::Actions::CadenceSignalAction for opt_out/manual_pause/replacement
# - ScanSolo::Handoff::TakeoverService (T41) for human takeover (RF-56)
class ScanSolo::Cadence::StopRecalculatePolicy
  TRIGGERS = %w[stage_changed won lost opt_out manual_pause replacement].freeze

  PAUSING_TRIGGERS = %w[manual_pause].freeze

  def self.call(opportunity:, trigger:)
    new(opportunity: opportunity, trigger: trigger).call
  end

  def self.handle_takeover(opportunity:)
    return if opportunity.blank?

    ScanSolo::Cadence::LifecycleService.cancel_all_for_opportunity!(opportunity)
  end

  def initialize(opportunity:, trigger:)
    @opportunity = opportunity
    @trigger = trigger.to_s
  end

  def call
    raise ArgumentError, "unknown cadence stop trigger: #{trigger}" unless TRIGGERS.include?(trigger)
    return if opportunity.blank?

    if PAUSING_TRIGGERS.include?(trigger)
      ScanSolo::Cadence::LifecycleService.pause_all_for_opportunity!(opportunity)
    else
      ScanSolo::Cadence::LifecycleService.cancel_all_for_opportunity!(opportunity)
    end
  end

  private

  attr_reader :opportunity, :trigger
end
