# RF-20/RF-29: recalculates cadence when a conversation returns to AI. The
# enrollment paused by takeover/handoff for the opportunity's current stage is
# resumed through LifecycleService.resume!, which shifts its remaining
# scheduled attempts by the paused duration; when the current stage has no
# open enrollment at all, a fresh one is created through StageEntryEnroller
# (which skips opted-out contacts and stages without a cadence).
class ScanSolo::Cadence::ResumeOnReturnService
  def self.call(opportunity:)
    new(opportunity: opportunity).call
  end

  def initialize(opportunity:)
    @opportunity = opportunity
  end

  def call
    cadence_definition = ScanSolo::CadenceDefinition.current_for(opportunity.stage)
    enrollment = ScanSolo::CadenceEnrollment.open_for(opportunity, cadence_definition).first
    return ScanSolo::Cadence::StageEntryEnroller.call(opportunity: opportunity) if enrollment.blank?

    ScanSolo::Cadence::LifecycleService.resume!(enrollment)
  end

  private

  attr_reader :opportunity
end
