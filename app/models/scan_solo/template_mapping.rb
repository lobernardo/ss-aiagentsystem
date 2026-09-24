# == Schema Information
#
# Table name: scan_solo_template_mappings
#
#  id            :bigint           not null, primary key
#  language      :string           not null
#  params        :jsonb            not null
#  stage         :string           not null
#  step          :integer
#  template_name :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#
# Indexes
#
#  idx_on_account_id_stage_step_c33edb498d          (account_id,stage,step) UNIQUE NULLS NOT DISTINCT
#  index_scan_solo_template_mappings_on_account_id  (account_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
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
