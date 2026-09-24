# RF-50: the sole writer of knowledge sources created, edited or removed by
# an administrator. Each write records one `knowledge_source.created`,
# `knowledge_source.updated` or `knowledge_source.deleted` audit event with
# the source title and changed field names (never the content). Indexing
# itself stays on ScanSolo::KnowledgeSource's commit hook (RF-43).
class ScanSolo::Knowledge::SourceWriteService
  def self.create!(account:, actor:, attributes:, file: nil)
    source = ScanSolo::KnowledgeSource.new(attributes.merge(account: account, added_by: actor))
    source.file.attach(file) if file.present?

    ActiveRecord::Base.transaction do
      source.save!
      audit!(source, actor, 'knowledge_source.created', source_type: source.source_type)
    end
    source
  end

  def self.update!(source:, actor:, attributes:)
    ActiveRecord::Base.transaction do
      source.update!(attributes)
      audit!(source, actor, 'knowledge_source.updated', changed_fields: source.saved_changes.keys - %w[updated_at])
    end
    source
  end

  def self.destroy!(source:, actor:)
    ActiveRecord::Base.transaction do
      audit!(source, actor, 'knowledge_source.deleted')
      source.destroy!
    end
  end

  def self.audit!(source, actor, event_type, payload = {})
    ScanSolo::AuditLogger.record!(
      subject: source, event_type: event_type, actor: actor, correlation_id: SecureRandom.uuid,
      payload: payload.merge(title: source.title)
    )
  end
  private_class_method :audit!
end
