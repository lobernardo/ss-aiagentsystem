json.cadence_evidence @cadence_evidence do |enrollment|
  json.partial! 'api/v1/accounts/scan_solo/cadence_enrollments/cadence_enrollment', resource: enrollment
  json.attempts enrollment.attempts.order(:step) do |attempt|
    json.id attempt.id
    json.step attempt.step
    json.cadence_version attempt.cadence_version
    json.template_reference attempt.template_reference
    json.scheduled_at attempt.scheduled_at
    json.sent_at attempt.sent_at
    json.result attempt.result
  end
end

json.make_errors do
  json.dead_letters @make_dead_letters do |make_request|
    json.id make_request.id
    json.action make_request.action
    json.correlation_id make_request.correlation_id
    json.idempotency_key make_request.idempotency_key
    json.retry_count make_request.retry_count
    json.status make_request.status
    json.created_at make_request.created_at
  end

  json.callback_errors @make_callback_errors do |callback|
    json.id callback.id
    json.action callback.action
    json.correlation_id callback.correlation_id
    json.signature_valid callback.signature_valid
    json.applied callback.applied
    json.rejection_reason callback.rejection_reason
    json.created_at callback.created_at
  end
end

json.audit_events @audit_events do |event|
  json.id event.id
  json.event_type event.event_type
  json.subject_type event.subject_type
  json.subject_id event.subject_id
  json.actor_type event.actor_type
  json.actor_id event.actor_id
  json.correlation_id event.correlation_id
  json.payload event.payload
  json.created_at event.created_at
end
