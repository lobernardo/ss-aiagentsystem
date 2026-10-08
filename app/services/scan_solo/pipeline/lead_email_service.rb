# RF-09 / CT-09: writes the lead's e-mail on the opportunity's native
# Contact, the address the proposal is delivered to (RF-08). The controller
# has already refused a malformed or empty address (`invalid_email`); the
# native Contact uniqueness (per account, case-insensitive) is the conflict
# rule, so an address already used by another contact raises
# `contact_conflict` and leaves the contact unchanged.
class ScanSolo::Pipeline::LeadEmailService
  def self.call(**)
    new(**).call
  end

  def initialize(opportunity:, email:)
    @opportunity = opportunity
    @email = email
  end

  def call
    contact.update!(email: email)
  rescue ActiveRecord::RecordInvalid
    raise unless contact.errors.of_kind?(:email, :taken)

    contact.restore_attributes
    raise CustomExceptions::ScanSolo::LeadEmailRejected, 'contact_conflict'
  end

  private

  attr_reader :opportunity, :email

  def contact
    opportunity.contact
  end
end
