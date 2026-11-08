# RF-15..RF-17 / RF-20 / CT-07: "Marcar proposta enviada manualmente".
#
# Closes an open quote request as `handled_manually` when the proposal was sent
# outside the system. Eligibility is checked under the request row lock, so a
# concurrent commercial reply or a second manual action finds it closed (RF-20).
# In one transaction: the opportunity moves to `proposta_enviada` through the
# sole stage path (unless already there), the request records who and when, and
# 1 `quote_request.handled_manually` audit is written. In `bulk` mode every
# active/paused post-proposal enrollment is cancelled too, so no legacy lead
# gets a follow-up (`cadence_skipped: legacy_bulk`); `single` keeps the
# enrollment created by the transition. Nothing is sent to anyone (RF-17).
class ScanSolo::Quote::HandledManuallyService
  TARGET_STAGE = 'proposta_enviada'.freeze
  ELIGIBLE_STAGES = %w[qualificado proposta_enviada].freeze
  MODES = %w[single bulk].freeze
  EVENT_TYPE = 'quote_request.handled_manually'.freeze

  def self.call(opportunity:, actor:, mode:)
    new(opportunity: opportunity, actor: actor, mode: mode).call
  end

  def initialize(opportunity:, actor:, mode:)
    raise ArgumentError, "unknown mode: #{mode}" unless MODES.include?(mode)

    @opportunity = opportunity
    @actor = actor
    @mode = mode
  end

  def call
    quote_request = ScanSolo::QuoteRequest.find_by(opportunity_id: opportunity.id)
    reject!('quote_request_missing') if quote_request.nil?

    quote_request.with_lock do
      reject!('quote_request_closed') unless quote_request.open?

      opportunity.reload
      reject!('invalid_stage') unless ELIGIBLE_STAGES.include?(opportunity.stage)

      apply!(quote_request)
    end

    opportunity
  end

  private

  attr_reader :opportunity, :actor, :mode

  def apply!(quote_request)
    previous_status = quote_request.status
    from_stage = opportunity.stage

    if from_stage != TARGET_STAGE
      ScanSolo::Pipeline::StageTransitionService.new(opportunity: opportunity, target_stage: TARGET_STAGE, actor: actor).call
    end
    quote_request.update!(status: :handled_manually, handled_manually_at: Time.current, handled_manually_by: actor)
    cancel_post_proposal_cadence! if bulk?

    ScanSolo::AuditLogger.record!(
      subject: opportunity, actor: actor, event_type: EVENT_TYPE, correlation_id: quote_request.correlation_id,
      payload: {
        quote_request_id: quote_request.id, previous_status: previous_status, from_stage: from_stage, to_stage: TARGET_STAGE, mode: mode,
        **(bulk? ? { cadence_skipped: 'legacy_bulk' } : {})
      }
    )
  end

  def cancel_post_proposal_cadence!
    ScanSolo::CadenceEnrollment.joins(:cadence_definition)
                               .where(opportunity_id: opportunity.id, status: %i[active paused],
                                      cadence_definition: { stage: TARGET_STAGE })
                               .find_each { |enrollment| ScanSolo::Cadence::LifecycleService.cancel!(enrollment) }
  end

  def bulk?
    mode == 'bulk'
  end

  def reject!(code)
    raise CustomExceptions::ScanSolo::HandledManuallyRejected, code
  end
end
