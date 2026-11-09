# Relatórios RF-01/RF-02/RF-03: the single commercial-status rule. It reads the
# opportunity's quote request and the current proposal version and returns the
# first matching row of the RF-01 table. Pure: no queries, no writes. Every
# other caller (opportunity JSON, report summary, stall list) asks this object.
# Escalação comercial RF-17/CT-04: an escalated opportunity (see
# PipelineOpportunity#escalated_to_commercial?) is `escalado_wa`, below the
# 3 proposal states and replacing nao_encaminhado/aguardando_artur/
# resposta_recebida. Not escalated, the table is unchanged.
class ScanSolo::Reports::CommercialStatus
  VALUES = %w[
    nao_encaminhado
    aguardando_artur
    resposta_recebida
    proposta_em_aprovacao
    proposta_enviada
    proposta_enviada_manual
    escalado_wa
  ].freeze

  def self.call(quote_request:, current_version:, escalated:)
    return 'nao_encaminhado' if quote_request.nil? && !escalated

    proposal_status(quote_request, current_version) || (escalated ? 'escalado_wa' : request_status(quote_request))
  end

  def self.proposal_status(quote_request, current_version)
    return 'proposta_enviada_manual' if quote_request&.handled_manually?
    return 'proposta_enviada' if current_version&.sent?

    'proposta_em_aprovacao' if current_version&.awaiting_approval?
  end

  def self.request_status(quote_request)
    quote_request.open? ? 'aguardando_artur' : 'resposta_recebida'
  end

  # RF-02: the instant the request was sent to the commercial contact.
  def self.forwarded_at(quote_request)
    quote_request&.sent_at
  end
  private_class_method :proposal_status, :request_status
end
