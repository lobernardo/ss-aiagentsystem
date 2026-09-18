# Blocks an outbound message that states a transactional claim (price,
# delivery status, proposal-send confirmation) unless that claim was
# produced by a deterministic registered action/service result for this
# turn (RF-41) — the primary anti-hallucination boundary before send, a
# hard block rather than a warning. validated_claims is the caller-supplied
# record of which claim types this specific turn's action layer actually
# produced (e.g. a validated proposal.generate/proposal.send result); no
# claim type is ever considered validated by default.
class ScanSolo::AiTurn::OutputValidator
  PRICE_PATTERN = /r\$\s?\d|\b\d+([.,]\d{2})?\s?reais\b/i
  PROPOSAL_SENT_PATTERN = /proposta (foi )?enviada|enviei a proposta/i
  DELIVERY_STATUS_PATTERN = /pedido entregue|entrega confirmada|status da entrega/i

  CLAIM_PATTERNS = {
    price: PRICE_PATTERN,
    proposal_sent: PROPOSAL_SENT_PATTERN,
    delivery_status: DELIVERY_STATUS_PATTERN
  }.freeze

  def self.call(content:, validated_claims: {})
    new(content: content, validated_claims: validated_claims).call
  end

  def initialize(content:, validated_claims: {})
    @content = content.to_s
    @validated_claims = validated_claims
  end

  def call
    violation = detect_violation
    { blocked: violation.present?, violation: violation }
  end

  private

  attr_reader :content, :validated_claims

  def detect_violation
    CLAIM_PATTERNS.each do |claim, pattern|
      return claim if pattern.match?(content) && !validated_claims[claim]
    end

    nil
  end
end
