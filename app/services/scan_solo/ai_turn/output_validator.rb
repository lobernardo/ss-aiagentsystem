# Blocks an outbound message that states a transactional claim (price,
# delivery status, proposal-send confirmation) unless that claim was
# produced by a deterministic registered action/service result for this
# turn (RF-41) — the primary anti-hallucination boundary before send, a
# hard block rather than a warning. validated_claims is the caller-supplied
# record of which claim types this specific turn's action layer actually
# produced (e.g. a validated proposal.generate/proposal.send result); no
# claim type is ever considered validated by default.
#
# RF-06: any entry of the published config's `restricted_information` found
# in the output (case-insensitively) blocks it as well.
class ScanSolo::AiTurn::OutputValidator
  PRICE_PATTERN = /r\$\s?\d|\b\d+([.,]\d{2})?\s?reais\b/i
  PROPOSAL_SENT_PATTERN = /proposta (foi )?enviada|enviei a proposta/i
  DELIVERY_STATUS_PATTERN = /pedido entregue|entrega confirmada|status da entrega/i

  CLAIM_PATTERNS = {
    price: PRICE_PATTERN,
    proposal_sent: PROPOSAL_SENT_PATTERN,
    delivery_status: DELIVERY_STATUS_PATTERN
  }.freeze

  def self.call(content:, validated_claims: {}, restricted_information: [])
    new(content: content, validated_claims: validated_claims, restricted_information: restricted_information).call
  end

  def initialize(content:, validated_claims: {}, restricted_information: [])
    @content = content.to_s
    @validated_claims = validated_claims
    @restricted_information = Array(restricted_information).compact_blank
  end

  def call
    violation = detect_violation
    { blocked: violation.present?, violation: violation }
  end

  private

  attr_reader :content, :validated_claims, :restricted_information

  def detect_violation
    return :restricted_information if restricted_information.any? { |entry| content.downcase.include?(entry.to_s.downcase) }

    CLAIM_PATTERNS.each do |claim, pattern|
      return claim if pattern.match?(content) && !validated_claims[claim]
    end

    nil
  end
end
