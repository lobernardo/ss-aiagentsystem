json.cadence_evidence @feed.cadence_evidence do |enrollment|
  json.partial! 'api/v1/accounts/scan_solo/cadence_enrollments/cadence_enrollment', resource: enrollment
  json.attempts enrollment.attempts.sort_by(&:step) do |attempt|
    json.id attempt.id
    json.step attempt.step
    json.cadence_version attempt.cadence_version
    json.template_reference attempt.template_reference
    json.scheduled_at attempt.scheduled_at
    json.sent_at attempt.sent_at
    json.result attempt.result
    json.message_id attempt.message_id
    json.last_block_reason attempt.last_block_reason
    json.last_checked_at attempt.last_checked_at
    json.external_error attempt.external_error
  end
end

json.template_availability @feed.template_availability do |row|
  json.partial! 'api/v1/accounts/scan_solo/cadence_templates/row', row: row
end

json.make_errors do
  json.dead_letters @feed.dead_letters do |dead_letter|
    make_request = dead_letter.make_request
    json.id make_request.id
    json.action make_request.action
    json.correlation_id make_request.correlation_id
    json.idempotency_key make_request.idempotency_key
    json.retry_count make_request.retry_count
    json.status make_request.status
    json.proposal_id dead_letter.proposal_version&.proposal_id
    json.proposal_version_id dead_letter.proposal_version&.id
    json.created_at make_request.created_at
  end

  json.callback_errors @feed.callback_errors do |callback|
    json.id callback.id
    json.action callback.action
    json.correlation_id callback.correlation_id
    json.signature_valid callback.signature_valid
    json.applied callback.applied
    json.rejection_reason callback.rejection_reason
    json.created_at callback.created_at
  end
end

json.handoff_events @feed.handoff_events do |event|
  json.id event.id
  json.conversation_id event.conversation_id
  json.event_type event.event_type
  json.trigger event.trigger
  json.actor_type event.actor_type
  json.actor_id event.actor_id
  json.correlation_id event.correlation_id
  json.created_at event.created_at
end

json.recent_errors @feed.recent_errors do |error|
  json.kind error.kind
  json.id error.id
  json.reason error.reason
  json.correlation_id error.correlation_id
  json.occurred_at error.occurred_at
end

json.audit_events @feed.audit_events do |event|
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
