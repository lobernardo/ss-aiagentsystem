# Lead state RF-14, RF-23, RF-24, RF-25, CT-03: the model's way to record the
# contact's intent, the next action, an action the customer asked for or
# authorized, and whether it sees an interpretation risk. Every write goes
# through ScanSolo::LeadState::Writer with the turn's inbound message as
# origin; `interpretation_risk` is only returned as evidence (RF-25 is
# enforced by the prompt), and so is `negotiation_requested`, read by
# ScanSolo::AiTurn::AttemptRunner after the actions (RF-35). Recording a next action or an authorization runs
# no side effect -- no proposal, handoff, e-mail or AI control change.
# proposta-template-local RF-37, CT-10: `collection_mode` is the lead's answer
# to the bulk collection offer; the Writer keeps it only once and only after
# the offer, and an ignored choice comes back as `collection_mode_ignored`.
# The offer itself is recorded by the system, never by this action (RF-36).
class ScanSolo::Actions::LeadStateUpdateAction
  CLASSIFICATION = :automatic

  SCHEMA = {
    'type' => 'object',
    'properties' => {
      'opportunity_id' => { 'type' => 'integer' },
      'intent' => { 'type' => 'string', 'enum' => ScanSolo::LeadState::INTENTS },
      'next_action' => { 'type' => 'string', 'enum' => ScanSolo::LeadState::NEXT_ACTIONS },
      'authorized_action' => { 'type' => 'string', 'enum' => ScanSolo::LeadState::NEXT_ACTIONS },
      'interpretation_risk' => { 'type' => 'boolean' },
      'negotiation_requested' => { 'type' => 'boolean' },
      'collection_mode' => { 'type' => 'string', 'enum' => ScanSolo::LeadState::COLLECTION_MODES }
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
    intent, next_action, authorized_action, collection_mode = params.values_at(:intent, :next_action, :authorized_action, :collection_mode)

    writer.set_intent!(intent: intent, source_message_id: turn.message_id) if intent
    writer.record_next_action!(value: next_action, source_message_id: turn.message_id) if next_action
    writer.authorize_action!(action: authorized_action, source_message_id: turn.message_id) if authorized_action
    mode_outcome = writer.set_collection_mode!(mode: collection_mode, source_message_id: turn.message_id) if collection_mode

    {
      opportunity_id: opportunity.id,
      **params.slice(:intent, :next_action, :authorized_action, :interpretation_risk, :negotiation_requested, :collection_mode),
      **(mode_outcome == :ignored ? { collection_mode_ignored: true } : {})
    }
  end

  private

  attr_reader :params, :turn
end
