# RF-48 "locate/update allowed contact qualification fields": filters the
# submitted fields down to the published agent config's
# required_qualification_fields allowlist before writing to the contact
# (only "allowed" fields are ever persisted), then auto-transitions the
# opportunity's stage as a deterministic side effect of that write --
# RF-15 (first qualification-field update on an em_contato opportunity
# starts qualification) and RF-16 (every required field satisfied moves it
# to qualificado). Both rules are evaluated here, never as separate
# model-invoked actions, so they cannot fire out of order or twice.
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
  end

  def call
    opportunity = ScanSolo::PipelineOpportunity.find_by!(conversation_id: params[:conversation_id])
    contact = opportunity.contact
    allowed_fields = allowed_qualification_fields(opportunity)

    filtered = (params[:fields] || {}).stringify_keys.slice(*allowed_fields)
    contact.update!(custom_attributes: contact.custom_attributes.merge(filtered)) if filtered.present?

    transition_stage!(opportunity, allowed_fields, contact)

    { opportunity_id: opportunity.id, contact_id: contact.id, updated_fields: filtered.keys }
  end

  private

  attr_reader :params, :actor

  def allowed_qualification_fields(opportunity)
    config = ScanSolo::AiAgentConfig.published_for(opportunity.account)
    Array(config&.required_qualification_fields)
  end

  def transition_stage!(opportunity, allowed_fields, contact)
    if opportunity.em_contato?
      ScanSolo::Pipeline::StageTransitionService.new(opportunity: opportunity, target_stage: :em_qualificacao, actor: actor).call
    elsif opportunity.em_qualificacao? && all_required_fields_satisfied?(allowed_fields, contact)
      ScanSolo::Pipeline::StageTransitionService.new(opportunity: opportunity, target_stage: :qualificado, actor: actor).call
    end
  end

  def all_required_fields_satisfied?(allowed_fields, contact)
    return false if allowed_fields.blank?

    allowed_fields.all? { |field| contact.custom_attributes[field].present? }
  end
end
