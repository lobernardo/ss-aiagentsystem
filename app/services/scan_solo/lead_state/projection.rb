# RF-03, RF-04, RF-09, RF-15, RF-17, RF-22, RNF-02: read-only view of an
# opportunity's lead state -- the CT-01 `lead_state` shape plus the ordered
# keys the agent may still ask about. Nothing is written and no LLM or HTTP
# is called, so the same state, config and pending updates always project
# the same way.
#
# - Classification: `obrigatorio` iff the key is one of the resolver's
#   required canonical keys, whatever the intent or stage (RF-15).
# - Status block: derived, never stored. `missing_fields` (required keys not
#   satisfied) comes from ScanSolo::Qualification::FieldResolver, the only
#   reader of "satisfied?" (RF-08); `next_follow_up_at` is the same earliest
#   active-enrollment attempt the opportunity JSON exposes.
# - Eligible keys: only `faltante` fields, required before complementary, in
#   RF-02 order; none once the qualification is `concluida` (RF-22).
# - Pending updates (attachment/link extractions of the current message,
#   always `inferido`) are overlaid in memory under the Writer's RF-07 rule,
#   so a field they fill is no longer eligible (RF-17).
class ScanSolo::LeadState::Projection
  Result = Struct.new(:intent, :qualification, :next_action, :authorized_actions, :blocks, :status, :history, :eligible_keys,
                      keyword_init: true)

  def self.call(opportunity:, config:, pending_updates: [])
    new(opportunity: opportunity, config: config, pending_updates: pending_updates).call
  end

  def initialize(opportunity:, config:, pending_updates:)
    @opportunity = opportunity
    @lead_state = opportunity.lead_state
    @resolver = ScanSolo::Qualification::FieldResolver.call(opportunity: opportunity, config: config)
    @pending_updates = pending_updates
  end

  def call
    Result.new(
      intent: lead_state.intent,
      qualification: { status: lead_state.qualification_status, completed_at: lead_state.qualification_completed_at },
      next_action: next_action,
      authorized_actions: lead_state.authorized_actions.map { |entry| entry.symbolize_keys.slice(:action, :source_message_id, :recorded_at) },
      blocks: blocks,
      status: status,
      history: history,
      eligible_keys: eligible_keys
    )
  end

  private

  attr_reader :opportunity, :lead_state, :resolver, :pending_updates

  def fields
    @fields ||= ScanSolo::Qualification::FieldResolver::CATALOG.map do |entry|
      stored = lead_state.fields.fetch(entry[:key], {})
      {
        key: entry[:key], label: entry[:label], value: stored['value'], status: stored['status'] || 'faltante',
        classification: required_keys.include?(entry[:key]) ? 'obrigatorio' : 'complementar', updated_at: stored['updated_at'],
        source_message_id: stored['source_message_id'], source_attachment_id: stored['source_attachment_id']
      }.merge(pending_overlay(entry[:key], stored['status'] || 'faltante'))
    end
  end

  def pending_overlay(key, current_status)
    update = pending_updates.reverse.find { |candidate| candidate[:key] == key && candidate[:value].present? }
    return {} unless update && ScanSolo::LeadState::Writer.applicable?(current_status: current_status, new_status: 'inferido')

    { value: update[:value], status: 'inferido', source_message_id: update[:source_message_id], source_attachment_id: update[:source_attachment_id] }
  end

  def required_keys
    @required_keys ||= resolver.required_canonical_keys
  end

  def blocks
    ScanSolo::Qualification::FieldResolver::CATALOG.zip(fields)
                                                   .group_by { |entry, _field| entry[:block] }
                                                   .transform_values { |pairs| pairs.map(&:last) }
  end

  def next_action
    return if lead_state.next_action.nil?

    { value: lead_state.next_action, recorded_at: lead_state.next_action_recorded_at, source_message_id: lead_state.next_action_source_message_id }
  end

  def status
    {
      stage: opportunity.stage,
      confirmed_fields: fields.select { |field| field[:status] == 'confirmado' }.pluck(:key),
      missing_fields: resolver.fields.reject(&:satisfied?).map(&:canonical_key).uniq,
      next_action: lead_state.next_action,
      owner_id: opportunity.owner_id,
      last_customer_interaction_at: opportunity.last_customer_interaction_at,
      next_follow_up_at: opportunity.cadence_enrollments.active.minimum(:next_attempt_at)
    }
  end

  def history
    lead_state.events.sort_by { |event| [event.created_at, event.id] }.map do |event|
      {
        subject: event.subject, key: event.key, previous_value: event.previous_value, previous_status: event.previous_status,
        new_value: event.new_value, new_status: event.new_status, source_message_id: event.source_message_id,
        source_attachment_id: event.source_attachment_id, changed_at: event.created_at
      }
    end
  end

  def eligible_keys
    return [] if lead_state.concluida?

    missing = fields.select { |field| field[:status] == 'faltante' }
    missing.partition { |field| field[:classification] == 'obrigatorio' }.flatten.pluck(:key)
  end
end
