# Applied to inbound content before model invocation (RF-38): flags a hit
# against the agent's configured forbidden_subjects, and bounds the actions
# available to the model for the turn per the agent's autonomy policy —
# proposal.approve/proposal.send always stay outside the per-turn allowlist
# here; only the confirmation flow (a later phase) can grant them, so the
# returned list is always a strict subset of the full registered-action
# vocabulary, never "all registered actions" (RF-38 AC). `proposal_generate`
# is offered only while the proposal integration is configured (RF-12,
# RF-36).
class ScanSolo::AiTurn::InputGuardrail
  ALL_ACTIONS = %w[
    qualification_field stage_transition private_note proposal_generate
    proposal_approve proposal_send cadence_signal human_handoff
  ].freeze

  CONFIRMATION_ONLY_ACTIONS = %w[proposal_approve proposal_send].freeze

  def self.call(config:, content:)
    new(config: config, content: content).call
  end

  def initialize(config:, content:)
    @config = config
    @content = content.to_s
  end

  def call
    {
      blocked: forbidden_subject_hit.present?,
      forbidden_subject_hit: forbidden_subject_hit,
      allowed_actions: allowed_actions
    }
  end

  private

  attr_reader :config, :content

  def forbidden_subject_hit
    Array(config.forbidden_subjects).find do |subject|
      subject.to_s.present? && content.downcase.include?(subject.to_s.downcase)
    end
  end

  def allowed_actions
    actions = ALL_ACTIONS - CONFIRMATION_ONLY_ACTIONS
    ScanSolo::Proposal::Integration.configured? ? actions : actions - ['proposal_generate']
  end
end
