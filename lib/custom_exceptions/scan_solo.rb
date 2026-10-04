module CustomExceptions::ScanSolo
end

class CustomExceptions::ScanSolo::ProposalIntegrationNotConfigured < StandardError; end
class CustomExceptions::ScanSolo::CadenceDefinitionMissing < StandardError; end
class CustomExceptions::ScanSolo::Forbidden < StandardError; end

# RF-05/RF-09: a "Novo lead" registration refused by a database-dependent rule
# (`contact_opted_out`, `contact_conflict`, `opportunity_exists`); the
# controller maps it to 422 `{ error: code }` (+ `opportunity_id`).
class CustomExceptions::ScanSolo::ManualLeadRejected < StandardError
  attr_reader :code, :opportunity_id

  def initialize(code, opportunity_id = nil)
    @code = code
    @opportunity_id = opportunity_id
    super(code)
  end
end

# RF-14: the published quote inbox setup cannot carry the quote e-mails;
# `reason` ∈ quote_inbox_missing, quote_inbox_not_email, quote_inbox_allowlisted.
class CustomExceptions::ScanSolo::QuoteInboxMisconfigured < StandardError
  attr_reader :reason

  def initialize(reason)
    @reason = reason
    super(reason)
  end
end

# RNF-01: an e-mail message would be created inside an open transaction.
class CustomExceptions::ScanSolo::DeliveryInsideTransaction < StandardError; end

# RF-39: a negotiation notification adapter answered failure; reported to the
# tracker without undoing the negotiation.
class CustomExceptions::ScanSolo::NegotiationNotificationFailed < StandardError; end

# RF-56 / CT-12: a manual quote-request resend refused; the controller maps it
# to 422 `{ error: code }` (quote_request_closed, quote_request_not_eligible,
# quote_inbox_misconfigured).
class CustomExceptions::ScanSolo::QuoteRequestResendRejected < StandardError
  attr_reader :code

  def initialize(code)
    @code = code
    super(code)
  end
end
