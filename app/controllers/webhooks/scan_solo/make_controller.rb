# CT-09 / RF-85 / RF-86 / RF-87 / RNF-06: the sole unauthenticated-caller-
# reachable endpoint in the whole ScanSolo layer, so every rejection path
# fails closed with zero persisted state change (RF-89). Trust decisions
# live entirely in ScanSolo::Make::CallbackVerifier (T68); this controller
# only turns that decision into exactly one ScanSolo::MakeCallback row and,
# only when accepted, the corresponding ScanSolo::MakeRequest status
# update. A duplicate/replayed correlation id can never insert a second
# ScanSolo::MakeCallback row (the DB-level permanent unique index, RNF-06),
# so a repeat delivery is acknowledged without reapplying anything.
class Webhooks::ScanSolo::MakeController < ActionController::API
  def process_callback
    raw_body = request.body.read
    result = ScanSolo::Make::CallbackVerifier.call(raw_body: raw_body, signature: request.headers['X-Make-Signature'])

    return head :unauthorized if result.rejection_reason == 'invalid_signature'
    return head :ok if result.valid? && already_processed?(result.payload['correlation_id'])

    if result.valid?
      apply!(result)
      head :ok
    else
      record_rejection!(result)
      head :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    # RNF-06: correlation id already has a callback row -- acknowledge the
    # redelivery without reapplying the side effect a second time. This is
    # a backstop for a genuine race against the `already_processed?` check
    # above; the DB-level permanent unique index is the actual guarantee.
    head :ok
  end

  private

  def already_processed?(correlation_id)
    ScanSolo::MakeCallback.exists?(correlation_id: correlation_id)
  end

  def apply!(result)
    ScanSolo::MakeCallback.create!(
      correlation_id: result.payload['correlation_id'],
      action: result.payload['action'],
      signature_valid: true,
      applied: true,
      payload: result.payload
    )

    result.make_request.update!(status: result.payload['status'] == 'success' ? :completed : :failed)
  end

  def record_rejection!(result)
    ScanSolo::MakeCallback.create!(
      correlation_id: result.payload&.dig('correlation_id'),
      action: result.payload&.dig('action'),
      signature_valid: result.signature_valid,
      applied: false,
      rejection_reason: result.rejection_reason,
      payload: result.payload || {}
    )
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    nil
  end
end
