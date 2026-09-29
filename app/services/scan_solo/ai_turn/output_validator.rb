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
#
# Lead state (RF-11, RF-12, RF-17, RF-22, RNF-02): given the projection of
# the state already changed by this attempt (ScanSolo::LeadState::Projection)
# and the model's `asked_fields`, after the checks above, in order:
# - `qualification_closed`: the qualification is `concluida` and a field is asked;
# - `question_limit`: more than 2 fields are asked;
# - `confirmed_field_question`: a `confirmado` key is asked, or a sentence
#   ending in "?" contains, as a token sequence after FieldResolver
#   normalization, the label or an alias with 2+ tokens of a `confirmado`
#   field (1-token spellings are not detected lexically, decision M5);
# - `field_not_missing`: an asked key is outside the catalog or not `faltante`.
# These four are the ones the turn regenerates once (RF-11a). Pure: no
# writes, LLM or HTTP.
class ScanSolo::AiTurn::OutputValidator
  PRICE_PATTERN = /r\$\s?\d|\b\d+([.,]\d{2})?\s?reais\b/i
  PROPOSAL_SENT_PATTERN = /proposta (foi )?enviada|enviei a proposta/i
  DELIVERY_STATUS_PATTERN = /pedido entregue|entrega confirmada|status da entrega/i

  CLAIM_PATTERNS = {
    price: PRICE_PATTERN,
    proposal_sent: PROPOSAL_SENT_PATTERN,
    delivery_status: DELIVERY_STATUS_PATTERN
  }.freeze

  REGENERABLE_VIOLATIONS = %i[confirmed_field_question question_limit field_not_missing qualification_closed].freeze
  QUESTION_LIMIT = 2

  def self.call(content:, validated_claims: {}, restricted_information: [], asked_fields: [], lead_state: nil)
    new(content: content, validated_claims: validated_claims, restricted_information: restricted_information, asked_fields: asked_fields,
        lead_state: lead_state).call
  end

  def initialize(content:, validated_claims: {}, restricted_information: [], asked_fields: [], lead_state: nil)
    @content = content.to_s
    @validated_claims = validated_claims
    @restricted_information = Array(restricted_information).compact_blank
    @asked_fields = asked_fields
    @lead_state = lead_state
  end

  def call
    violation = detect_violation
    { blocked: violation.present?, violation: violation }
  end

  private

  attr_reader :content, :validated_claims, :restricted_information, :asked_fields, :lead_state

  def detect_violation
    return :restricted_information if restricted_information.any? { |entry| content.downcase.include?(entry.to_s.downcase) }

    CLAIM_PATTERNS.each do |claim, pattern|
      return claim if pattern.match?(content) && !validated_claims[claim]
    end

    lead_state_violation if lead_state
  end

  def lead_state_violation
    return :qualification_closed if lead_state.qualification[:status] == 'concluida' && asked_fields.any?
    return :question_limit if asked_fields.size > QUESTION_LIMIT
    return :confirmed_field_question if confirmed_field_asked?

    :field_not_missing if asked_fields.any? { |key| field_statuses[key] != 'faltante' }
  end

  def field_statuses
    @field_statuses ||= lead_state.blocks.values.flatten.to_h { |field| [field[:key], field[:status]] }
  end

  def confirmed_field_asked?
    confirmed = field_statuses.select { |_key, status| status == 'confirmado' }.keys
    return true if asked_fields.intersect?(confirmed)

    spellings = confirmed.flat_map { |key| multi_token_spellings(key) }
    question_phrases.any? { |phrase| spellings.any? { |spelling| "_#{phrase}_".include?("_#{spelling}_") } }
  end

  def multi_token_spellings(key)
    label = ScanSolo::Qualification::FieldResolver::CATALOG.find { |entry| entry[:key] == key }[:label]
    spellings = [ScanSolo::Qualification::FieldResolver.normalize(label), *ScanSolo::Qualification::FieldResolver::SPELLINGS.fetch(key, [])]
    spellings.uniq.select { |spelling| spelling.include?('_') }
  end

  def question_phrases
    content.scan(/[^.!?\n]*\?/).map { |sentence| ScanSolo::Qualification::FieldResolver.normalize(sentence.gsub(/[[:punct:]]/, ' ')) }
  end
end
