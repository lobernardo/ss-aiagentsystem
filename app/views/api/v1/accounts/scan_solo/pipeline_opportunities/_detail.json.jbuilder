json.partial! 'api/v1/accounts/scan_solo/pipeline_opportunities/pipeline_opportunity', resource: @opportunity
json.lead_state do
  json.partial! 'api/v1/accounts/scan_solo/pipeline_opportunities/lead_state', lead_state: @lead_state
end
# CT-02 / UI-04 / UI-05: quote request, current proposal and the latest
# failure of the manual lead's initial template (RF-08, from the audit trail).
quote_request = @opportunity.quote_request
if quote_request
  json.quote_request do
    json.id quote_request.id
    json.status quote_request.status
    json.sent_at quote_request.sent_at
    json.replied_at quote_request.replied_at
    json.email_conversation_id quote_request.email_conversation_id
  end
else
  json.quote_request nil
end

version = @opportunity.proposal&.current_version
if version
  json.proposal do
    json.version_number version.version_number
    json.proposal_number version.proposal_number
    json.status version.status
    json.value version.value
    json.currency version.currency
    json.valid_until version.valid_until
    json.document_url version.document_url
    json.failure_reason version.failure_reason
  end
else
  json.proposal nil
end

failure = ScanSolo::AuditEvent.where(subject: @opportunity, event_type: [ScanSolo::Pipeline::ManualLeadOutreach::BLOCKED_EVENT,
                                                                         ScanSolo::Messaging::DeliveryReconciler::MANUAL_LEAD_FAILED_EVENT])
                              .order(:created_at, :id).last
if failure
  blocked = failure.event_type == ScanSolo::Pipeline::ManualLeadOutreach::BLOCKED_EVENT
  json.initial_template_failure do
    json.reason blocked ? failure.payload['reason'] : failure.payload['external_error']
    json.status blocked ? 'blocked' : 'failed'
    json.occurred_at failure.created_at
  end
else
  json.initial_template_failure nil
end
