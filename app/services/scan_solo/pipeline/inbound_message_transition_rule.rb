# RF-14: moves a "Novo Lead" opportunity to "Em Contato" on the first real
# inbound message. Firing is naturally limited to exactly once per
# opportunity: after the transition the opportunity is no longer novo_lead,
# so a subsequent message is a no-op.
class ScanSolo::Pipeline::InboundMessageTransitionRule
  def self.call(message:)
    new(message: message).call
  end

  def initialize(message:)
    @message = message
  end

  def call
    return unless message.incoming?

    opportunity = ScanSolo::PipelineOpportunity.find_by(conversation_id: message.conversation_id)
    return if opportunity.blank?
    return unless opportunity.novo_lead?

    ScanSolo::Pipeline::StageTransitionService.new(
      opportunity: opportunity,
      target_stage: :em_contato
    ).call
  end

  private

  attr_reader :message
end
