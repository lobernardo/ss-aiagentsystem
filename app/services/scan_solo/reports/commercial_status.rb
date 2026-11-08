# Relatórios RF-01/RF-02/RF-03: the single commercial-status rule. It reads the
# opportunity's quote request and the current proposal version and returns the
# first matching row of the RF-01 table. Pure: no queries, no writes. Every
# other caller (opportunity JSON, report summary, stall list) asks this object.
# `escalado_wa` is out of scope (Fatia 2).
class ScanSolo::Reports::CommercialStatus
  VALUES = %w[
    nao_encaminhado
    aguardando_artur
    resposta_recebida
    proposta_em_aprovacao
    proposta_enviada
    proposta_enviada_manual
  ].freeze

  def self.call(quote_request:, current_version:)
    return 'nao_encaminhado' if quote_request.nil?
    return 'proposta_enviada_manual' if quote_request.handled_manually?
    return 'proposta_enviada' if current_version&.sent?
    return 'proposta_em_aprovacao' if current_version&.awaiting_approval?
    return 'aguardando_artur' if quote_request.open?

    'resposta_recebida'
  end

  # RF-02: the instant the request was sent to the commercial contact.
  def self.forwarded_at(quote_request)
    quote_request&.sent_at
  end
end
