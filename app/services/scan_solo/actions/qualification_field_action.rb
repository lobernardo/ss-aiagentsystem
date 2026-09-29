# RF-48 "locate/update allowed contact qualification fields"; lead state
# RF-06, RF-07, RF-08, CT-03. Every submitted key is resolved through
# ScanSolo::Qualification::FieldResolver (normalization + canonical aliases,
# RF-09). Each entry is a string (the customer stated it: `confirmado`) or
# `{value, status}` with status `confirmado` | `inferido` (deduced by the
# model).
#
# - A key of the RF-02 catalog is written to the opportunity's lead state
#   through ScanSolo::LeadState::Writer, with the turn's inbound message as
#   origin: a new or corrected value becomes current and the previous one
#   goes to history (RF-06); an `inferido` value never replaces a
#   `confirmado` one and is reported as `confirmed_value_kept` (RF-07).
# - An applied value is mirrored on the Contact as before (RF-08): a native
#   field (`nome`/`email`/`telefone`) only when the column is blank and the
#   value valid (RF-10), anything else merged under its canonical
#   `custom_attributes` key without touching any existing key (RF-21).
# - A published required label outside the catalog is only mirrored; any
#   other key is never persisted and is reported verbatim (RF-11).
# All accepted pairs of a call land in a single contact save.
#
# RF-15: a call carrying a required field on an em_contato opportunity
# starts qualification. Reaching `qualificado` is the lead state completion
# (ScanSolo::LeadState::CompletionService), never this action.
class ScanSolo::Actions::QualificationFieldAction
  CLASSIFICATION = :automatic

  SCHEMA = {
    'type' => 'object',
    'properties' => {
      'conversation_id' => { 'type' => 'integer' },
      'fields' => {
        'type' => 'object',
        'additionalProperties' => {
          'oneOf' => [
            { 'type' => 'string' },
            {
              'type' => 'object',
              'properties' => { 'value' => { 'type' => 'string' }, 'status' => { 'enum' => %w[confirmado inferido] } },
              'required' => %w[value status],
              'additionalProperties' => false
            }
          ]
        }
      }
    },
    'required' => %w[conversation_id fields],
    'additionalProperties' => false
  }.freeze

  def self.call(params:, actor: nil, turn: nil, **)
    new(params: params, actor: actor, turn: turn).call
  end

  def initialize(params:, actor:, turn:)
    @params = params
    @actor = actor
    @turn = turn
    @updated_fields = []
    @not_applied_fields = []
    @unrecognized_fields = []
    @state_changes = []
    @accepted_keys = []
    @native_fields = {}
    @custom_values = {}
  end

  def call
    @opportunity = ScanSolo::PipelineOpportunity.find_by!(conversation_id: params[:conversation_id])
    @contact = opportunity.contact
    @config = ScanSolo::AiAgentConfig.published_for(opportunity.account)
    @writer = ScanSolo::LeadState::Writer.new(lead_state: opportunity.lead_state)

    write_fields!
    start_qualification!

    {
      opportunity_id: opportunity.id, contact_id: contact.id, updated_fields: updated_fields,
      not_applied_fields: not_applied_fields, unrecognized_fields: unrecognized_fields, state_changes: state_changes
    }
  end

  private

  attr_reader :params, :actor, :turn, :opportunity, :contact, :config, :writer, :updated_fields, :not_applied_fields,
              :unrecognized_fields, :state_changes, :accepted_keys, :native_fields, :custom_values

  def write_fields!
    (params[:fields] || {}).each do |key, entry|
      value, status = entry.is_a?(Hash) ? entry.values_at(:value, :status) : [entry, 'confirmado']
      assign_field(key.to_s, value, status)
    end
    drop_invalid_native_fields
    contact.custom_attributes = contact.custom_attributes.merge(custom_values) if custom_values.present?
    contact.save! if contact.changed?
  end

  def required_keys
    @required_keys ||= ScanSolo::Qualification::FieldResolver.call(opportunity: opportunity, config: config).required_canonical_keys
  end

  def assign_field(key, value, status)
    canonical = ScanSolo::Qualification::FieldResolver.canonical_key(key)

    if ScanSolo::Qualification::FieldResolver::CATALOG_KEYS.include?(canonical)
      write_state_field(key, canonical, value, status)
    elsif required_keys.include?(canonical)
      mirror_custom(key, canonical, value)
    else
      unrecognized_fields << key
    end
  end

  def write_state_field(key, canonical, value, status)
    outcome = writer.apply_field!(key: canonical, value: value, status: status, source_message_id: turn.message_id)
    state_changes << { key: canonical, outcome: outcome }
    accepted_keys << canonical unless outcome == :ignored

    case outcome
    when :applied then mirror(key, canonical, value.strip)
    when :kept_confirmed then not_applied_fields << { field: key, reason: 'confirmed_value_kept' }
    end
  end

  def mirror(key, canonical, value)
    attribute = ScanSolo::Qualification::FieldResolver::NATIVE[canonical]
    return mirror_custom(key, canonical, value) if attribute.nil?

    if contact.public_send(attribute).present?
      not_applied_fields << { field: key, reason: 'native_already_present' }
    else
      contact.public_send("#{attribute}=", value)
      native_fields[attribute] = key
    end
  end

  def mirror_custom(key, canonical, value)
    custom_values[canonical] = value
    updated_fields << key
    accepted_keys << canonical
  end

  # RF-10: an invalid native value (email format/uniqueness, E.164 phone) is
  # restored to its persisted value and reported, so the remaining pairs
  # still save.
  def drop_invalid_native_fields
    contact.valid?

    native_fields.each do |attribute, key|
      if contact.errors[attribute].present?
        contact.restore_attributes([attribute])
        not_applied_fields << { field: key, reason: contact.errors.full_messages_for(attribute).join(', ') }
      else
        updated_fields << key
      end
    end
  end

  # Native keys accepted outside the published required list never drive a
  # transition (RF-12).
  def start_qualification!
    return unless opportunity.em_contato? && accepted_keys.intersect?(required_keys)

    ScanSolo::Pipeline::StageTransitionService.new(opportunity: opportunity, target_stage: :em_qualificacao, actor: actor).call
  end
end
