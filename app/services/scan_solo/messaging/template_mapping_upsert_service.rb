# RF-32/RF-50: creates or replaces the account's template mapping for a
# (stage, step) -- `step: nil` is the proposal send -- and records one
# `template_mapping.updated` audit event with the administrator as actor.
class ScanSolo::Messaging::TemplateMappingUpsertService
  def self.call(account:, actor:, attributes:)
    new(account: account, actor: actor, attributes: attributes).call
  end

  def initialize(account:, actor:, attributes:)
    @account = account
    @actor = actor
    @attributes = attributes
  end

  def call
    mapping = ScanSolo::TemplateMapping.find_or_initialize_by(account: account, stage: attributes[:stage], step: attributes[:step])

    ActiveRecord::Base.transaction do
      mapping.update!(template_name: attributes[:template_name], language: attributes[:language], params: attributes[:params])
      ScanSolo::AuditLogger.record!(
        subject: mapping, event_type: 'template_mapping.updated', actor: actor, correlation_id: SecureRandom.uuid,
        payload: { stage: mapping.stage, step: mapping.step, template_name: mapping.template_name, language: mapping.language }
      )
    end

    mapping
  end

  private

  attr_reader :account, :actor, :attributes
end
