# RF-22/RF-23: creates the conversation's single ScanSolo::PipelineOpportunity
# on its first eligible inbound message. `create_or_find_by!` relies on the
# unique index on conversation_id, so two concurrent jobs for the same
# conversation converge on one row; only the caller that actually inserted
# it records the audit event and the Novo Lead enrollment.
class ScanSolo::Pipeline::OpportunityBootstrapService
  Result = Struct.new(:opportunity, :created, keyword_init: true) do
    def created?
      created
    end
  end

  def self.call(message:)
    new(message: message).call
  end

  def initialize(message:)
    @message = message
    @conversation = message.conversation
  end

  def call
    opportunity = ScanSolo::PipelineOpportunity.create_or_find_by!(conversation_id: conversation.id) do |record|
      record.account_id = conversation.account_id
      record.contact_id = conversation.contact_id
      record.owner_id = conversation.assignee_id
      record.stage = :novo_lead
      record.last_customer_interaction_at = message.created_at
    end
    created = opportunity.previously_new_record?

    record_creation!(opportunity) if created

    Result.new(opportunity: opportunity, created: created)
  end

  private

  attr_reader :message, :conversation

  def record_creation!(opportunity)
    ScanSolo::AuditLogger.record!(
      subject: opportunity,
      event_type: 'pipeline.opportunity_created',
      correlation_id: SecureRandom.uuid,
      payload: { conversation_id: conversation.id, message_id: message.id }
    )
    ScanSolo::Cadence::StageEntryEnroller.call(opportunity: opportunity)
  end
end
