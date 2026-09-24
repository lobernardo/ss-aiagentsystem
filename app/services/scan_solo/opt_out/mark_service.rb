# RF-16/RF-31: the single writer that opts a contact out of ScanSolo cadences,
# used by both the inbound keyword match (source `keyword`) and the model's
# `cadence_signal` opt_out action (source `model_action`). Every active or
# paused enrollment of the contact's opportunities is cancelled through the
# existing StopRecalculatePolicy `opt_out` trigger. The marker is only ever
# cleared by ScanSolo::OptOut::ClearService (RF-63).
class ScanSolo::OptOut::MarkService
  def self.call(contact:, source:)
    new(contact: contact, source: source).call
  end

  def initialize(contact:, source:)
    @contact = contact
    @source = source
  end

  def call
    ActiveRecord::Base.transaction do
      extension = ScanSolo::ContactExtension.resolve_for(contact)
      extension.update!(opted_out: true, opted_out_at: Time.current, opted_out_source: source) unless extension.opted_out?

      ScanSolo::PipelineOpportunity.where(contact: contact).find_each do |opportunity|
        ScanSolo::Cadence::StopRecalculatePolicy.call(opportunity: opportunity, trigger: 'opt_out')
      end

      extension
    end
  end

  private

  attr_reader :contact, :source
end
