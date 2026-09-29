# RF-01, RF-14, RF-15, RF-21, RF-23, RF-24: one lead state per opportunity.
class ScanSolo::LeadState < ApplicationRecord
  self.table_name = 'scan_solo_lead_states'

  INTENTS = %w[orcamento avaliacao_tecnica convite_cotacao envio_documentos duvida verificar_capacidade localizar_rede visita acompanhar_proposta
               outro].freeze
  NEXT_ACTIONS = %w[proposta avaliacao_tecnica solicitar_documentos atendimento_humano aguardar_cliente].freeze
  FIELD_STATUSES = %w[confirmado inferido faltante].freeze
  DEFAULT_NEXT_ACTION_BY_INTENT = {
    'orcamento' => 'proposta',
    'convite_cotacao' => 'proposta',
    'avaliacao_tecnica' => 'avaliacao_tecnica',
    'visita' => 'avaliacao_tecnica',
    'localizar_rede' => 'avaliacao_tecnica',
    'envio_documentos' => 'solicitar_documentos',
    'acompanhar_proposta' => 'aguardar_cliente',
    'duvida' => 'aguardar_cliente',
    'verificar_capacidade' => 'aguardar_cliente',
    'outro' => 'aguardar_cliente',
    nil => 'aguardar_cliente'
  }.freeze

  belongs_to :opportunity, class_name: 'ScanSolo::PipelineOpportunity', inverse_of: :lead_state
  has_many :events, class_name: 'ScanSolo::LeadStateEvent', inverse_of: :lead_state, dependent: :destroy

  enum qualification_status: { em_andamento: 0, concluida: 1 }

  # One state per opportunity is enforced by the unique index only, so
  # ScanSolo::LeadState::InitializeService's create_or_find_by! converges
  # concurrent creators on the same row.
  validates :intent, inclusion: { in: INTENTS }, allow_nil: true
  validates :next_action, inclusion: { in: NEXT_ACTIONS }, allow_nil: true
end
