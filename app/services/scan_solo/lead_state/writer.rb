# Sole writer of ScanSolo::LeadState / ScanSolo::LeadStateEvent rows
# (RF-06, RF-07, RF-14, RF-21, RF-23, RF-24, RNF-06). Every operation locks
# the state row and saves it once, inside the caller's transaction; each
# change of value, status, intent or next action appends exactly one
# history event, and events are only ever created -- never updated or
# removed.
class ScanSolo::LeadState::Writer
  # RF-07: an `inferido` value never replaces a `confirmado` one.
  def self.applicable?(current_status:, new_status:)
    !(current_status == 'confirmado' && new_status == 'inferido')
  end

  def initialize(lead_state:)
    @lead_state = lead_state
  end

  # `status` is `confirmado` or `inferido`, as enforced by the calling action
  # schema; extractions are always `inferido`.
  def apply_field!(key:, value:, status:, source_message_id:, source_attachment_id: nil)
    raise ArgumentError, "unknown lead state field: #{key}" unless ScanSolo::Qualification::FieldResolver::CATALOG_KEYS.include?(key)

    value = value.to_s.strip
    return :ignored if value.blank?

    lead_state.lock!
    current = lead_state.fields.fetch(key, {})
    previous_status = current['status'] || 'faltante'
    return :kept_confirmed unless self.class.applicable?(current_status: previous_status, new_status: status)
    return :unchanged if current['value'] == value && previous_status == status

    write_field!(key, current, 'value' => value, 'status' => status, 'source_message_id' => source_message_id,
                               'source_attachment_id' => source_attachment_id)
    :applied
  end

  def set_intent!(intent:, source_message_id:)
    lead_state.lock!
    previous = lead_state.intent
    return :unchanged if previous == intent

    lead_state.update!(intent: intent)
    lead_state.events.create!(subject: 'intent', previous_value: previous, new_value: intent, source_message_id: source_message_id)
    :applied
  end

  # A nil source_message_id only comes from the RF-01a backfill.
  def record_next_action!(value:, source_message_id:)
    lead_state.lock!
    previous = lead_state.next_action
    lead_state.update!(next_action: value, next_action_recorded_at: Time.current, next_action_source_message_id: source_message_id)
    lead_state.events.create!(subject: 'next_action', previous_value: previous, new_value: value, source_message_id: source_message_id)
    :applied
  end

  # CT-01 has no history subject for authorizations: the list itself is the
  # record, with one entry per action.
  def authorize_action!(action:, source_message_id:)
    raise ArgumentError, "invalid authorized action: #{action}" unless ScanSolo::LeadState::NEXT_ACTIONS.include?(action)

    lead_state.lock!
    return :unchanged if lead_state.authorized_actions.any? { |entry| entry['action'] == action }

    lead_state.update!(
      authorized_actions: lead_state.authorized_actions + [
        { 'action' => action, 'source_message_id' => source_message_id, 'recorded_at' => Time.current.iso8601(6) }
      ]
    )
    :applied
  end

  # RF-21: qualification completes once and never reopens.
  def complete!(at:)
    lead_state.lock!
    if lead_state.concluida?
      lead_state.errors.add(:qualification_status, 'already concluida')
      raise ActiveRecord::RecordInvalid, lead_state
    end

    lead_state.update!(qualification_status: :concluida, qualification_completed_at: at)
  end

  private

  attr_reader :lead_state

  def write_field!(key, current, entry)
    lead_state.fields = lead_state.fields.merge(key => entry.merge('updated_at' => Time.current.iso8601(6)))
    lead_state.save!
    lead_state.events.create!(subject: 'field', key: key, previous_value: current['value'], previous_status: current['status'] || 'faltante',
                              new_value: entry['value'], new_status: entry['status'], source_message_id: entry['source_message_id'],
                              source_attachment_id: entry['source_attachment_id'])
  end
end
