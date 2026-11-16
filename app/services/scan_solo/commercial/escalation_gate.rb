# Escalação filtrada RF-01/RF-03/RF-04/RF-05/RF-08/RF-11/RNF-03: the pure
# eligibility decision for the commercial WhatsApp link. No writes, LLM or
# HTTP; the only model-derived input is whether the turn carried a commercial
# request. Called only by ScanSolo::Commercial::EscalationService.
#
# previously_escalated never changes the decision: every commercial request
# after the link is an explicit request (RF-08). It is an input so the RF-11
# matrix is explicit.
module ScanSolo::Commercial::EscalationGate
  QUALIFIED_STAGES = %w[qualificado proposta_enviada negociacao].freeze

  # rubocop:disable Lint/UnusedMethodArgument
  def self.decide(stage:, quote_sent:, email_redirect_count:, commercial_request:, previously_escalated:)
    return :none unless commercial_request
    return :etapa_nao_qualificada unless QUALIFIED_STAGES.include?(stage.to_s)
    return :orcamento_nao_enviado unless quote_sent
    return :primeiro_pedido_email if email_redirect_count.zero?

    :approved
  end
  # rubocop:enable Lint/UnusedMethodArgument

  def self.quote_sent?(opportunity)
    opportunity.quote_request&.sent_at.present?
  end
end
