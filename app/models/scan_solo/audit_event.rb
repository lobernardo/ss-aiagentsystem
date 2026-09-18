class ScanSolo::AuditEvent < ApplicationRecord
  self.table_name = 'scan_solo_audit_events'

  belongs_to :subject, polymorphic: true
  belongs_to :actor, polymorphic: true, optional: true

  validates :event_type, presence: true
  validates :correlation_id, presence: true

  def readonly?
    persisted?
  end
end
