# Lead state RF-14, RF-23, RF-24, RF-25, CT-03: the model's way to record the
# contact's intent, the next action, an action the customer asked for or
# authorized, and whether it sees an interpretation risk. Every write goes
# through ScanSolo::LeadState::Writer with the turn's inbound message as
# origin; `interpretation_risk` is only returned as evidence (RF-25 is
# enforced by the prompt). Recording a next action or an authorization runs
# no side effect -- no proposal, handoff, e-mail or AI control change.
class ScanSolo::Actions::LeadStateUpdateAction
  CLASSIFICATION = :automatic

  SCHEMA = {
    'type' => 'object',
    'properties' => {
      'opportunity_id' => { 'type' => 'integer' },
      'intent' => { 'type' => 'string', 'enum' => ScanSolo::LeadState::INTENTS },
      'next_action' => { 'type' => 'string', 'enum' => ScanSolo::LeadState::NEXT_ACTIONS },
      'authorized_action' => { 'type' => 'string', 'enum' => ScanSolo::LeadState::NEXT_ACTIONS },
      'interpretation_risk' => { 'type' => 'boolean' }
    },
    'required' => %w[opportunity_id],
    'additionalProperties' => false
  }.freeze

  def self.call(params:, turn:, **)
    new(params: params, turn: turn).call
  end

  def initialize(params:, turn:)
    @params = params
    @turn = turn
  end

  def call
    opportunity = ScanSolo::PipelineOpportunity.find(params[:opportunity_id])
    writer = ScanSolo::LeadState::Writer.new(lead_state: opportunity.lead_state)
    intent, next_action, authorized_action = params.values_at(:intent, :next_action, :authorized_action)

    writer.set_intent!(intent: intent, source_message_id: turn.message_id) if intent
    writer.record_next_action!(value: next_action, source_message_id: turn.message_id) if next_action
    writer.authorize_action!(action: authorized_action, source_message_id: turn.message_id) if authorized_action

    { opportunity_id: opportunity.id, **params.slice(:intent, :next_action, :authorized_action, :interpretation_risk) }
  end

  private

  attr_reader :params, :turn
end
