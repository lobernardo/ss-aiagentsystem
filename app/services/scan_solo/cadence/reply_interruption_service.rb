# RF-43: every customer reply interrupts the cadence that was already running
# when it arrived -- the next `scheduled` attempt of each active enrollment
# older than the message is cancelled, whatever the reply says and whatever
# its AI turn ends up being. The remaining attempts keep their `scheduled_at`.
#
# At most one attempt is cancelled per cycle: a cycle starts at the last
# non-private outgoing message before the reply, and the cycle marker is the
# `cadence.attempt_interrupted_by_reply` audit itself (keyed by the message
# that caused it), so a burst of replies with no outgoing message in between
# cancels only once. The enrollment row lock serializes such a burst.
#
# RF-18 (scansolo-proposta-aprovacao-email): in `proposta_enviada` a lead
# reply (WhatsApp or the proposal e-mail thread) cancels every `scheduled`
# attempt of each active enrollment older than the message, with one audit
# per cancelled attempt; `sent`/`dispatched` attempts are untouched.
class ScanSolo::Cadence::ReplyInterruptionService
  EVENT_TYPE = 'cadence.attempt_interrupted_by_reply'.freeze

  def self.call(opportunity:, message:)
    new(opportunity: opportunity, message: message).call
  end

  def initialize(opportunity:, message:)
    @opportunity = opportunity
    @message = message
  end

  def call
    opportunity.cadence_enrollments.active.where('created_at < ?', message.created_at).find_each do |enrollment|
      enrollment.with_lock do
        next unless enrollment.active?

        if opportunity.proposta_enviada?
          enrollment.attempts.scheduled.order(:scheduled_at).each { |attempt| cancel!(enrollment, attempt) }
        elsif !interrupted_in_cycle?(enrollment)
          interrupt!(enrollment)
        end
      end
    end
  end

  private

  attr_reader :opportunity, :message

  def interrupt!(enrollment)
    attempt = enrollment.attempts.scheduled.order(:scheduled_at).first
    cancel!(enrollment, attempt) if attempt
  end

  def cancel!(enrollment, attempt)
    ScanSolo::Cadence::AttemptEvidenceRecorder.record_cancelled!(attempt)
    ScanSolo::AuditLogger.record!(
      subject: enrollment, event_type: EVENT_TYPE, correlation_id: SecureRandom.uuid,
      payload: { enrollment_id: enrollment.id, attempt_id: attempt.id, message_id: message.id }
    )
  end

  def interrupted_in_cycle?(enrollment)
    cycle_replies = message.conversation.messages.incoming
    cycle_replies = cycle_replies.where('created_at > ?', cycle_start) if cycle_start

    ScanSolo::AuditEvent.where(subject: enrollment, event_type: EVENT_TYPE)
                        .exists?(["payload ->> 'message_id' IN (?)", cycle_replies.pluck(:id).map(&:to_s)])
  end

  def cycle_start
    return @cycle_start if defined?(@cycle_start)

    @cycle_start = message.conversation.messages.outgoing.where(private: false)
                          .where('created_at < ?', message.created_at).maximum(:created_at)
  end
end
