# RF-63: the only reset path for a contact's opt-out marker -- an explicit
# administrator action (authorized by ScanSolo::ContactOptOutPolicy at the
# controller boundary) recorded as `contact.opt_out_cleared`. Nothing clears
# the marker automatically, including later inbound messages.
class ScanSolo::OptOut::ClearService
  def self.call(contact:, actor:)
    new(contact: contact, actor: actor).call
  end

  def initialize(contact:, actor:)
    @contact = contact
    @actor = actor
  end

  def call
    extension = ScanSolo::ContactExtension.resolve_for(contact)
    return extension unless extension.opted_out?

    ActiveRecord::Base.transaction do
      extension.update!(opted_out: false, opted_out_at: nil, opted_out_source: nil)
      ScanSolo::AuditLogger.record!(
        subject: contact,
        event_type: 'contact.opt_out_cleared',
        actor: actor,
        correlation_id: SecureRandom.uuid,
        payload: { contact_id: contact.id }
      )
    end

    extension
  end

  private

  attr_reader :contact, :actor
end
