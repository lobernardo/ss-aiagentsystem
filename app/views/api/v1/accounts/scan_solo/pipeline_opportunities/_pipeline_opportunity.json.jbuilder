json.id resource.id
json.account_id resource.account_id
json.contact_id resource.contact_id
json.contact_name resource.contact.name
# CT-01 / RF-09: the lead e-mail the proposal is delivered to (UI-03).
json.lead_email resource.contact.email
json.conversation_id resource.conversation_id
json.owner_id resource.owner_id
json.stage resource.stage
json.last_customer_interaction_at resource.last_customer_interaction_at
# RF-11/RF-63: next scheduled follow-up across this opportunity's active
# cadence enrollments (earliest wins if more than one is active). The index
# passes it precomputed for the whole list (RNF-06).
json.next_follow_up_at local_assigns.key?(:next_follow_up_at) ? next_follow_up_at : resource.cadence_enrollments.active.minimum(:next_attempt_at)
json.created_at resource.created_at
json.updated_at resource.updated_at
# UI-02: chronological stage history (RF-07 records).
json.stage_history resource.stage_events.sort_by(&:created_at) do |event|
  json.id event.id
  json.from_stage event.from_stage
  json.to_stage event.to_stage
  json.actor_type event.actor_type
  json.actor_id event.actor_id
  json.created_at event.created_at
end
# CT-02 / UI-02: card data. Lead-state values are display only -- a
# `faltante` field shows as null; FieldResolver still decides satisfaction.
lead_fields = resource.lead_state&.fields.to_h
json.lead_source resource.lead_source
{ company: 'empresa', service: 'tipo_servico', city_uf: 'cidade_uf' }.each do |attribute, key|
  field = lead_fields[key].to_h
  json.set! attribute, field['status'] == 'faltante' ? nil : field['value']
end
json.ai_control_state resource.conversation_extension&.ai_control_state || 'ai_active'
json.quote_request_status resource.quote_request&.status
json.proposal_status resource.proposal&.current_version&.status
