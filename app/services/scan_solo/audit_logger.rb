class ScanSolo::AuditLogger
  def self.record!(subject:, event_type:, correlation_id:, actor: nil, payload: {})
    ScanSolo::AuditEvent.create!(
      subject: subject,
      event_type: event_type,
      actor: actor,
      correlation_id: correlation_id,
      payload: payload
    )
  end
end
