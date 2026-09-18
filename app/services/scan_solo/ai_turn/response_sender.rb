# Sends the model's approved final response only through native Chatwoot
# outbound messaging — the same `conversation.messages.create!` path human
# replies use, never a parallel send mechanism (RF-43). The outbound message
# and the turn's evidence update happen inside one transaction so the
# persisted usage/evidence record and the delivered message content can
# never diverge (RF-43's "persisted content is identical to what was sent").
# Called from inside ScanSolo::AiTurn::TurnOrchestrator's own transaction, so
# action_evidence (already executed by the time this runs, RF-44) commits or
# rolls back atomically with the send.
class ScanSolo::AiTurn::ResponseSender
  def self.call(message:, config:, result:, turn:, action_evidence: [])
    new(message: message, config: config, result: result, turn: turn, action_evidence: action_evidence).call
  end

  def initialize(message:, config:, result:, turn:, action_evidence: [])
    @message = message
    @config = config
    @result = result
    @turn = turn
    @action_evidence = action_evidence
  end

  def call
    ActiveRecord::Base.transaction do
      outbound = create_outbound_message
      record_evidence!(outbound)
      outbound
    end
  end

  private

  attr_reader :message, :config, :result, :turn, :action_evidence

  def create_outbound_message
    conversation = message.conversation

    conversation.messages.create!(
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      message_type: :outgoing,
      content: result.content,
      sender: agent_bot
    )
  end

  def record_evidence!(outbound)
    turn.update!(
      invocation_status: :succeeded,
      model_provider: result.provider,
      model_reference: result.model,
      input_tokens: result.input_tokens,
      output_tokens: result.output_tokens,
      action_evidence: action_evidence,
      response_message_id: outbound.id
    )
  end

  def agent_bot
    AgentBot.find_or_create_by!(account: message.account, name: config.name.presence || 'ScanSolo AI Agent')
  end
end
