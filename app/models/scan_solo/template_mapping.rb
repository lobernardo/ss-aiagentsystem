class ScanSolo::TemplateMapping < ApplicationRecord
  self.table_name = 'scan_solo_template_mappings'

  PARAM_SOURCES = %w[contact_name contact_first_name agent_name stage_label static].freeze
  STAGES = %w[novo_lead em_contato em_qualificacao proposta_enviada].freeze

  belongs_to :account

  validates :stage, inclusion: { in: STAGES }, uniqueness: { scope: %i[account_id step] }
  validates :template_name, :language, presence: true
  validates :step, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate :proposal_step
  validate :parameter_sources

  private

  def proposal_step
    errors.add(:step, 'is required for cadence stages') if step.nil? && stage != 'proposta_enviada'
  end

  def parameter_sources
    unless params.is_a?(Array)
      errors.add(:params, 'must be an array')
      return
    end

    params.each { |param| validate_parameter(param) }
  end

  def validate_parameter(param)
    unless param.is_a?(Hash) && PARAM_SOURCES.include?(param['source'])
      errors.add(:params, 'contains an invalid source')
      return
    end
    return unless param['source'] == 'static'

    value = param['value']
    errors.add(:params, 'requires a string value for static sources') unless value.is_a?(String) && value.present?
  end
end
