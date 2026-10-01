# RF-32/RF-33, UI-12: one row per (stage, step) of every active cadence
# definition plus one row per CT-09 single-template slot (`step: nil`, in
# ScanSolo::TemplateMapping::SINGLE_TEMPLATES order), each with the
# resolved template (ScanSolo::Messaging::TemplateResolver) and its
# availability evaluated by ScanSolo::Cadence::TemplateAvailabilityGuard
# against the account's allowlisted WhatsApp inboxes. With several
# allowlisted WhatsApp inboxes the first blocking one is reported, since a
# send through it would be refused.
class ScanSolo::Messaging::TemplateAvailabilityReport
  def self.call(account:)
    new(account: account).call
  end

  def self.row(account:, stage:, step:)
    new(account: account).row(stage, step)
  end

  def initialize(account:)
    @account = account
  end

  def call
    cadence_rows = ScanSolo::TemplateMapping::STAGES.flat_map do |stage|
      definition = ScanSolo::CadenceDefinition.current_for(stage)
      next [] unless definition

      (1..definition.attempt_count).map { |step| row(stage, step) }
    end

    cadence_rows + ScanSolo::TemplateMapping::SINGLE_TEMPLATES.keys.map { |stage| row(stage, nil) }
  end

  def row(stage, step)
    template = ScanSolo::Messaging::TemplateResolver.definition_for(account: account, stage: stage, step: step)
    result = availability(template)

    {
      stage: stage, step: step, template_name: template.name, language: template.language, params: template.params,
      mapped: template.mapped?, availability: result.blocked? ? 'blocked' : 'available', block_reason: result.reason,
      meta_status: result.meta_status, last_synced_at: result.last_synced_at
    }
  end

  private

  attr_reader :account

  def availability(template)
    results = whatsapp_inboxes.map { |inbox| ScanSolo::Cadence::TemplateAvailabilityGuard.check(inbox: inbox, template: template) }
    results.find(&:blocked?) || results.first || ScanSolo::Cadence::TemplateAvailabilityGuard::Result.new(blocked: false)
  end

  def whatsapp_inboxes
    @whatsapp_inboxes ||= begin
      allowed_ids = ScanSolo::AiAgentConfig.published_for(account)&.allowed_inbox_ids.to_a
      account.inboxes.where(id: allowed_ids, channel_type: 'Channel::Whatsapp').includes(:channel).order(:id).to_a
    end
  end
end
