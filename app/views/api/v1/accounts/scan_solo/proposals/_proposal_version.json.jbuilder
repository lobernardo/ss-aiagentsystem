make_request = resource.make_request
json.id resource.id
json.proposal_id resource.proposal_id
json.version_number resource.version_number
json.status resource.status
json.is_current resource.is_current
json.value resource.value
json.currency resource.currency
json.artifact_url resource.artifact_url
json.failure_reason resource.failure_reason
json.correlation_id resource.correlation_id
json.approved_at resource.approved_at
json.approval_required resource.approval_required?
json.sent_at resource.send_callback_applied_at
json.retry_count make_request&.retry_count.to_i
json.dead_letter make_request&.dead_letter? || false
json.proposal_number resource.proposal_number
json.valid_until resource.valid_until
json.document_url resource.document_url
