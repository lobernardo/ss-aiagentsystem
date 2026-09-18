class ScanSolo::PipelineOpportunity < ApplicationRecord
  self.table_name = 'scan_solo_pipeline_opportunities'

  belongs_to :account
  belongs_to :contact
  belongs_to :conversation
  belongs_to :owner, class_name: 'User', optional: true

  has_many :stage_events,
           class_name: 'ScanSolo::PipelineStageEvent',
           foreign_key: :opportunity_id,
           inverse_of: :opportunity,
           dependent: :destroy

  enum stage: {
    novo_lead: 0,
    em_contato: 1,
    em_qualificacao: 2,
    qualificado: 3,
    proposta_enviada: 4,
    negociacao: 5,
    ganho: 6,
    perdido: 7
  }

  validates :conversation_id, uniqueness: true

  def record_customer_interaction!(at:)
    update!(last_customer_interaction_at: at)
  end
end
