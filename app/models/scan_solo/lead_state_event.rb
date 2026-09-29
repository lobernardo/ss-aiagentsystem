# RF-06, RNF-06: lead state history is append-only.
class ScanSolo::LeadStateEvent < ApplicationRecord
  self.table_name = 'scan_solo_lead_state_events'

  belongs_to :lead_state, class_name: 'ScanSolo::LeadState', inverse_of: :events

  validates :subject, inclusion: { in: %w[field intent next_action] }

  def readonly?
    persisted?
  end
end
