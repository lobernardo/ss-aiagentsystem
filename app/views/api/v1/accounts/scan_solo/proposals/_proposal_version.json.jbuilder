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
# CT-01: approval/rejection data and the delivery state (e-mail to the lead, WhatsApp notice).
json.approved_by resource.approved_by && { id: resource.approved_by.id, name: resource.approved_by.name }
json.rejected_at resource.rejected_at
json.rejected_by resource.rejected_by && { id: resource.rejected_by.id, name: resource.rejected_by.name }
json.rejection_reason resource.rejection_reason
# A message counts as sent once the native transport stored its `source_id` (RF-13).
message_status = lambda do |message|
  next 'failed' if message.failed?

  message.source_id.present? ? 'sent' : 'pending'
end
email_message = resource.sent_message if resource.sent_message&.inbox&.email?
json.delivery do
  # null for a version not delivered yet or delivered by the legacy WhatsApp flow.
  json.email_status email_message && message_status.call(email_message)
  json.notice_status(if resource.notice_message then message_status.call(resource.notice_message)
                     elsif resource.notice_failure_reason.present? then 'blocked'
                     end)
end
