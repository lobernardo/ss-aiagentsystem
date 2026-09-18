# RF-48 "create a private handoff/operational note" -- reuses the native
# Messages::MessageBuilder path (same one AutomationRules::ActionService
# uses for `add_private_note`) so the note lands in the same Message
# timeline as every other conversation event, never a parallel note store.
class ScanSolo::Actions::PrivateNoteAction
  CLASSIFICATION = :automatic

  SCHEMA = {
    'type' => 'object',
    'properties' => {
      'conversation_id' => { 'type' => 'integer' },
      'content' => { 'type' => 'string', 'minLength' => 1 }
    },
    'required' => %w[conversation_id content],
    'additionalProperties' => false
  }.freeze

  def self.call(params:, actor: nil, **)
    new(params: params, actor: actor).call
  end

  def initialize(params:, actor: nil)
    @params = params
    @actor = actor
  end

  def call
    conversation = Conversation.find(params[:conversation_id])

    Messages::MessageBuilder.new(actor, conversation, { content: params[:content], private: true }).perform
  end

  private

  attr_reader :params, :actor
end
