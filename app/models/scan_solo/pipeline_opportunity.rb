# == Schema Information
#
# Table name: scan_solo_pipeline_opportunities
#
#  id                           :bigint           not null, primary key
#  last_customer_interaction_at :datetime
#  stage                        :integer          default("novo_lead"), not null
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#  account_id                   :bigint           not null
#  contact_id                   :bigint           not null
#  conversation_id              :bigint           not null
#  owner_id                     :bigint
#
# Indexes
#
#  index_scan_solo_pipeline_opportunities_on_account_id       (account_id)
#  index_scan_solo_pipeline_opportunities_on_contact_id       (contact_id)
#  index_scan_solo_pipeline_opportunities_on_conversation_id  (conversation_id) UNIQUE
#  index_scan_solo_pipeline_opportunities_on_owner_id         (owner_id)
#
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
