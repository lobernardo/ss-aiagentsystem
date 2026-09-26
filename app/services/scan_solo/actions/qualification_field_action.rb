# RF-48 "locate/update allowed contact qualification fields": every
# submitted key is resolved through ScanSolo::Qualification::FieldResolver
# (normalization + canonical aliases, RF-09). A key that resolves to a
# native field (`nome`/`email`/`telefone`, required or not) is written to
# the contact column only when it is blank and valid (RF-10); one that
# resolves to a published required field is written under its canonical
# `custom_attributes` key without touching any existing key (RF-21); any
# other key is never persisted and is reported verbatim (RF-11). All
# accepted pairs of a call land in a single contact save.
#
# The stage then auto-transitions as a deterministic side effect of that
# write -- RF-15 (a call carrying a required field on an em_contato
# opportunity starts qualification) and RF-16 (the resolver reporting every
# required field satisfied moves it to qualificado). Both rules are
# evaluated here, never as separate model-invoked actions, so they cannot
# fire out of order or twice.
class ScanSolo::Actions::QualificationFieldAction
  CLASSIFICATION = :automatic

  SCHEMA = {
    'type' => 'object',
    'properties' => {
      'conversation_id' => { 'type' => 'integer' },
      'fields' => { 'type' => 'object' }
    },
    'required' => %w[conversation_id fields],
    'additionalProperties' => false
  }.freeze

  def self.call(params:, actor: nil, **)
    new(params: params, actor: actor).call
  end

  def initialize(params:, actor: nil)
    @params = params
    @actor = actor
    @updated_fields = []
    @not_applied_fields = []
    @unrecognized_fields = []
    @accepted_keys = []
    @native_fields = {}
    @custom_values = {}
  end

  def call
    opportunity = ScanSolo::PipelineOpportunity.find_by!(conversation_id: params[:conversation_id])
    @contact = opportunity.contact
    @config = ScanSolo::AiAgentConfig.published_for(opportunity.account)

    write_fields!
    transition_stage!(opportunity)

    {
      opportunity_id: opportunity.id, contact_id: contact.id, updated_fields: updated_fields,
      not_applied_fields: not_applied_fields, unrecognized_fields: unrecognized_fields
    }
  end

  private

  attr_reader :params, :actor, :contact, :config, :updated_fields, :not_applied_fields, :unrecognized_fields,
              :accepted_keys, :native_fields, :custom_values

  def write_fields!
    (params[:fields] || {}).each { |key, value| assign_field(key.to_s, value) }
    drop_invalid_native_fields
    contact.custom_attributes = contact.custom_attributes.merge(custom_values) if custom_values.present?
    contact.save! if contact.changed?
  end

  def required_keys
    @required_keys ||= ScanSolo::Qualification::FieldResolver.call(contact: contact, config: config).required_canonical_keys
  end

  def assign_field(key, value)
    canonical = ScanSolo::Qualification::FieldResolver.canonical_key(key)
    attribute = ScanSolo::Qualification::FieldResolver::NATIVE[canonical]
    return unrecognized_fields << key unless attribute || required_keys.include?(canonical)

    if attribute.nil?
      custom_values[canonical] = value
      updated_fields << key
      accepted_keys << canonical
    elsif contact.public_send(attribute).present?
      not_applied_fields << { field: key, reason: 'native_already_present' }
      accepted_keys << canonical
    else
      contact.public_send("#{attribute}=", value)
      native_fields[attribute] = [key, canonical]
    end
  end

  # RF-10: an invalid native value (email format/uniqueness, E.164 phone) is
  # restored to its persisted value and reported, so the remaining pairs
  # still save.
  def drop_invalid_native_fields
    contact.valid?

    native_fields.each do |attribute, (key, canonical)|
      if contact.errors[attribute].present?
        contact.restore_attributes([attribute])
        not_applied_fields << { field: key, reason: contact.errors.full_messages_for(attribute).join(', ') }
      else
        updated_fields << key
        accepted_keys << canonical
      end
    end
  end

  # Native keys accepted outside the published required list never drive a
  # transition (RF-12).
  def transition_stage!(opportunity)
    if opportunity.em_contato? && accepted_keys.intersect?(required_keys)
      ScanSolo::Pipeline::StageTransitionService.new(opportunity: opportunity, target_stage: :em_qualificacao, actor: actor).call
    elsif opportunity.em_qualificacao? && all_required_fields_satisfied?
      ScanSolo::Pipeline::StageTransitionService.new(opportunity: opportunity, target_stage: :qualificado, actor: actor).call
    end
  end

  def all_required_fields_satisfied?
    resolver = ScanSolo::Qualification::FieldResolver.call(contact: contact, config: config)
    resolver.fields.present? && resolver.missing_labels.empty?
  end
end
