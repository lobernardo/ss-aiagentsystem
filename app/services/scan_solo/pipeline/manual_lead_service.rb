# RF-04/RF-06/RF-09/RF-10: the "Novo lead" registration. The controller has
# already validated the input format; this service owns the database rules
# and creates Contact -> Conversation -> PipelineOpportunity in one
# transaction, serialized per account+phone by an advisory lock so two
# concurrent registrations of the same phone never create two contacts.
#
# The opportunity (lead_source `manual`, no customer interaction yet) starts
# in the operator's initial stage and gets that stage's cadence through
# ScanSolo::Cadence::StageEntryEnroller, the same entry used by every stage
# change. Only stages a brand-new lead can truly be in are accepted:
# proposta_enviada/negociacao need a real proposal and ganho a closed deal.
#
# A novo_lead opportunity also gets the manual initial template; its cadence
# step 1 is recorded `skipped` because that template replaces it, so steps
# 2..n keep their own offsets from the enrollment (RF-10). Other stages run
# their own cadence unchanged, and perdido gets none.
class ScanSolo::Pipeline::ManualLeadService
  Result = Struct.new(:opportunity, :contact_created, keyword_init: true)

  INITIAL_TEMPLATE_SKIP_REASON = 'manual_initial_template'.freeze
  INITIAL_STAGES = %w[novo_lead em_contato em_qualificacao qualificado perdido].freeze

  def self.call(**)
    new(**).call
  end

  def initialize(account:, actor:, name:, phone_number:, email:, company:, owner_id:, inbox:, initial_stage:) # rubocop:disable Metrics/ParameterLists
    @account = account
    @actor = actor
    @name = name
    @phone_number = phone_number
    @email = email
    @company = company
    @owner_id = owner_id
    @inbox = inbox
    @initial_stage = initial_stage
  end

  def call
    ActiveRecord::Base.transaction do
      lock_phone!
      contact, contact_created = resolve_contact!
      reject!('contact_opted_out') if ScanSolo::ContactExtension.opted_out?(contact)
      reject_open_opportunity!(contact)

      opportunity = ScanSolo::PipelineOpportunity.create!(
        account: account, contact: contact, conversation: resolve_conversation!(contact), stage: initial_stage,
        lead_source: 'manual', owner_id: owner_id, last_customer_interaction_at: nil
      )
      record_creation!(opportunity, contact_created)
      enroll!(opportunity)
      ActiveRecord.after_all_transactions_commit { ScanSolo::Pipeline::ManualLeadOutreach.call(opportunity: opportunity) } if opportunity.novo_lead?

      Result.new(opportunity: opportunity, contact_created: contact_created)
    end
  end

  private

  attr_reader :account, :actor, :name, :phone_number, :email, :company, :owner_id, :inbox, :initial_stage

  def lock_phone!
    ActiveRecord::Base.connection.execute(
      ActiveRecord::Base.sanitize_sql_array(['SELECT pg_advisory_xact_lock(hashtext(?))', "scansolo_manual_lead:#{account.id}:#{phone_number}"])
    )
  end

  def resolve_contact!
    by_phone = account.contacts.find_by(phone_number: phone_number)
    by_email = account.contacts.from_email(email) if email.present?
    reject!('contact_conflict') if by_phone && by_email && by_phone != by_email

    existing = by_phone || by_email
    return [existing, false] if existing

    [account.contacts.create!(name: name, phone_number: phone_number, email: email, custom_attributes: { 'empresa' => company }.compact), true]
  end

  def reject_open_opportunity!(contact)
    open_opportunity = ScanSolo::PipelineOpportunity.where(contact: contact)
                                                    .where.not(stage: ScanSolo::Pipeline::StageTransitionService::TERMINAL_STAGES)
                                                    .first
    reject!('opportunity_exists', open_opportunity.id) if open_opportunity
  end

  # Rodada 2: an open conversation of the contact in the chosen inbox that has
  # no opportunity yet is reused instead of opening a second thread.
  def resolve_conversation!(contact)
    conversation = contact.conversations.open.where(inbox: inbox)
                          .where.not(id: ScanSolo::PipelineOpportunity.select(:conversation_id))
                          .order(:created_at).last
    conversation ||= ConversationBuilder.new(
      params: ActionController::Parameters.new({}),
      contact_inbox: ContactInboxBuilder.new(contact: contact, inbox: inbox, source_id: phone_number.delete('+')).perform
    ).perform
    conversation.update!(assignee_id: owner_id) if owner_id
    conversation
  end

  def record_creation!(opportunity, contact_created)
    ScanSolo::AuditLogger.record!(
      subject: opportunity,
      event_type: 'pipeline.opportunity_created',
      actor: actor,
      correlation_id: SecureRandom.uuid,
      payload: { source: 'manual', conversation_id: opportunity.conversation_id, contact_created: contact_created, initial_stage: initial_stage }
    )
  end

  def enroll!(opportunity)
    enrollment = ScanSolo::Cadence::StageEntryEnroller.call(opportunity: opportunity)
    return if enrollment.blank? || !opportunity.novo_lead?

    ScanSolo::Cadence::AttemptEvidenceRecorder.new(enrollment.attempts.find_by!(step: 1))
                                              .record!(result: :skipped, last_block_reason: INITIAL_TEMPLATE_SKIP_REASON)
  end

  def reject!(code, opportunity_id = nil)
    raise CustomExceptions::ScanSolo::ManualLeadRejected.new(code, opportunity_id)
  end
end
