# RF-06, RNF-06: lead state history is append-only. RF-39: `collection_mode`
# events use `key` `collection_offered_at` or `collection_mode`.
class ScanSolo::LeadStateEvent < ApplicationRecord
  self.table_name = 'scan_solo_lead_state_events'

  belongs_to :lead_state, class_name: 'ScanSolo::LeadState', inverse_of: :events

  validates :subject, inclusion: { in: %w[field intent next_action collection_mode] }

  def readonly?
    persisted?
  end
end
