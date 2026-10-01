# == Schema Information
#
# Table name: scan_solo_pipeline_opportunities
#
#  id                           :bigint           not null, primary key
#  last_customer_interaction_at :datetime
#  lead_source                  :string
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
# Check Constraints
#
#  scan_solo_pipeline_opportunities_lead_source_check  (lead_source IN ('website','manual'))
#
class ScanSolo::PipelineOpportunity < ApplicationRecord
  self.table_name = 'scan_solo_pipeline_opportunities'

  # RF-01: structured lead origin; nil is the "Não informada" state.
  LEAD_SOURCES = %w[website manual].freeze

  belongs_to :account
  belongs_to :contact
  belongs_to :conversation
  belongs_to :owner, class_name: 'User', optional: true

  has_many :stage_events,
           class_name: 'ScanSolo::PipelineStageEvent',
           foreign_key: :opportunity_id,
           inverse_of: :opportunity,
           dependent: :destroy

  has_many :cadence_enrollments,
           class_name: 'ScanSolo::CadenceEnrollment',
           foreign_key: :opportunity_id,
           inverse_of: :opportunity,
           dependent: :destroy

  has_one :proposal,
          class_name: 'ScanSolo::Proposal',
          foreign_key: :opportunity_id,
          inverse_of: :opportunity,
          dependent: :destroy

  has_one :lead_state,
          class_name: 'ScanSolo::LeadState',
          foreign_key: :opportunity_id,
          inverse_of: :opportunity,
          dependent: :destroy

  has_one :quote_request,
          class_name: 'ScanSolo::QuoteRequest',
          foreign_key: :opportunity_id,
          inverse_of: :opportunity,
          dependent: :destroy

  # CT-02 / RNF-06: read-only path to the conversation's ai_control_state so
  # the pipeline index can preload it without touching Chatwoot's Conversation.
  has_one :conversation_extension,
          class_name: 'ScanSolo::ConversationExtension',
          primary_key: :conversation_id,
          foreign_key: :conversation_id,
          inverse_of: false,
          dependent: nil

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

  validates :lead_source, inclusion: { in: LEAD_SOURCES }, allow_nil: true

  # Lead state RF-01: every opportunity has its lead state from creation on.
  after_create { ScanSolo::LeadState::InitializeService.call(opportunity: self) }

  # One opportunity per conversation is enforced by the unique index only, so
  # ScanSolo::Pipeline::OpportunityBootstrapService's create_or_find_by! can
  # converge concurrent creators on the same row (RF-22).

  def record_customer_interaction!(at:)
    update!(last_customer_interaction_at: at)
  end
end
