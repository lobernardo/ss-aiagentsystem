# == Schema Information
#
# Table name: scan_solo_audit_events
#
#  id             :bigint           not null, primary key
#  actor_type     :string
#  event_type     :string           not null
#  payload        :jsonb            not null
#  subject_type   :string           not null
#  created_at     :datetime         not null
#  actor_id       :bigint
#  correlation_id :string           not null
#  subject_id     :bigint           not null
#
# Indexes
#
#  index_scan_solo_audit_events_on_actor_type_and_actor_id      (actor_type,actor_id)
#  index_scan_solo_audit_events_on_correlation_id               (correlation_id)
#  index_scan_solo_audit_events_on_event_type                   (event_type)
#  index_scan_solo_audit_events_on_subject_type_and_subject_id  (subject_type,subject_id)
#
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
