json.id resource.id
json.account_id resource.account_id
json.contact_id resource.contact_id
json.contact_name resource.contact.name
json.conversation_id resource.conversation_id
json.owner_id resource.owner_id
json.stage resource.stage
json.last_customer_interaction_at resource.last_customer_interaction_at
# Wired to the cadence engine's enrollment record in a later phase (T50).
json.next_follow_up_at nil
json.created_at resource.created_at
json.updated_at resource.updated_at
# UI-02: chronological stage history (RF-07 records).
json.stage_history resource.stage_events.order(:created_at) do |event|
  json.id event.id
  json.from_stage event.from_stage
  json.to_stage event.to_stage
  json.actor_type event.actor_type
  json.actor_id event.actor_id
  json.created_at event.created_at
end
