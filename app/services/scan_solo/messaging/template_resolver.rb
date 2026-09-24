# RF-32: resolves the WhatsApp template for a cadence (stage, step) or for
# the proposal send (`proposta_enviada`, step nil). A stored
# ScanSolo::TemplateMapping wins; absent one, the convention applies --
# `scansolo_cadence_<stage>_v<version>_step<n>` (or the proposal send
# default) in `pt_BR` with no parameters.
#
# Parameter values only ever come from the allowlisted
# ScanSolo::TemplateMapping::PARAM_SOURCES and are emitted in the native
# positional `processed_params` shape read by
# Whatsapp::TemplateProcessorService (`{'body' => {'1' => ..., '2' => ...}}`).
class ScanSolo::Messaging::TemplateResolver
  PROPOSAL_SEND_TEMPLATE = 'scansolo_proposal_send'.freeze
  DEFAULT_LANGUAGE = 'pt_BR'.freeze

  Template = Struct.new(:name, :language, :params, :mapped, :processed_params, keyword_init: true) do
    def mapped?
      mapped
    end

    def sender_params
      { language: language, processed_params: processed_params }
    end
  end

  # Name, language and parameter sources only -- no contact-specific values.
  def self.definition_for(account:, stage:, step:)
    mapping = ScanSolo::TemplateMapping.find_by(account: account, stage: stage.to_s, step: step)
    return Template.new(name: mapping.template_name, language: mapping.language, params: mapping.params, mapped: true) if mapping

    Template.new(name: convention_name(stage, step), language: DEFAULT_LANGUAGE, params: [], mapped: false)
  end

  def self.call(account:, stage:, step:, opportunity:)
    template = definition_for(account: account, stage: stage, step: step)
    values = template.params.map { |param| value_for(param, account: account, opportunity: opportunity) }
    template.processed_params = values.empty? ? {} : { 'body' => values.each_with_index.to_h { |value, index| [(index + 1).to_s, value] } }
    template
  end

  def self.convention_name(stage, step)
    return PROPOSAL_SEND_TEMPLATE if step.nil?

    ScanSolo::CadenceDefinition.current_for(stage).template_reference_for(step)
  end

  def self.value_for(param, account:, opportunity:)
    case param['source']
    when 'contact_name' then opportunity.contact.name.to_s
    when 'contact_first_name' then opportunity.contact.name.to_s.split.first.to_s
    when 'agent_name' then ScanSolo::AiAgentConfig.published_for(account)&.name.to_s
    when 'stage_label' then ScanSolo::Handoff::HandoffService::STAGE_LABELS.fetch(opportunity.stage)
    when 'static' then param['value']
    end
  end
  private_class_method :convention_name, :value_for
end
