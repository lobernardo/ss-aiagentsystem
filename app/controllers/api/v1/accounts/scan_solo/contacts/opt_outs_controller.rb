# CT-11 (+ derived read for UI-15): a contact's opt-out marker. Every account
# user may read it; only an administrator may clear it (RF-48), and
# ScanSolo::OptOut::ClearService is the marker's only reset path (RF-63).
# A contact of another account is not found (404).
class Api::V1::Accounts::ScanSolo::Contacts::OptOutsController < Api::V1::Accounts::ScanSolo::BaseController
  before_action :set_contact

  def show
    authorize(@contact, :show?, policy_class: ::ScanSolo::ContactOptOutPolicy)
    @opted_out = ::ScanSolo::ContactExtension.opted_out?(@contact)
  end

  def destroy
    authorize(@contact, :destroy?, policy_class: ::ScanSolo::ContactOptOutPolicy)
    @opted_out = ::ScanSolo::OptOut::ClearService.call(contact: @contact, actor: Current.user).opted_out?
    render :show
  end

  private

  def set_contact
    @contact = Current.account.contacts.find(params[:contact_id])
  end
end
