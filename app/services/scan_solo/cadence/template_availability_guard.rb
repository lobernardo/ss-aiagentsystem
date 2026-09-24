# RF-33: a cadence attempt or proposal send must never reach a WhatsApp
# inbox whose synced `message_templates` lack the resolved template
# (ScanSolo::Messaging::TemplateResolver) with the resolved language and
# status APPROVED, or whose BODY placeholder count differs from the mapped
# parameter count. The block reason is reported with the channel's
# `message_templates_last_updated` so an administrator can tell a stale sync
# from a real Meta rejection.
#
# A non-WhatsApp inbox (fake/test inbox) has no Meta template catalogue and
# is treated as available.
class ScanSolo::Cadence::TemplateAvailabilityGuard
  STATUS_REASONS = {
    'REJECTED' => 'template_rejected',
    'PAUSED' => 'template_paused',
    'PENDING' => 'template_pending',
    'DISABLED' => 'template_disabled'
  }.freeze
  PLACEHOLDER = /\{\{\s*([^}\s]+)\s*\}\}/

  Result = Struct.new(:blocked, :reason, :meta_status, :last_synced_at, keyword_init: true) do
    def blocked?
      blocked
    end
  end

  def self.check(inbox:, template:)
    new(inbox: inbox, template: template).check
  end

  def initialize(inbox:, template:)
    @channel = inbox.channel
    @template = template
  end

  def check
    return Result.new(blocked: false) unless channel.is_a?(Channel::Whatsapp)

    named = Array(channel.message_templates).select { |candidate| candidate['name'] == template.name }
    return blocked('template_missing') if named.empty?

    synced = named.find { |candidate| candidate['language'].to_s.casecmp?(template.language) }
    return blocked('language_unavailable') if synced.nil?

    check_synced(synced)
  end

  private

  attr_reader :channel, :template

  def check_synced(synced)
    status = synced['status'].to_s.upcase
    return blocked(STATUS_REASONS.fetch(status, 'template_pending'), status) unless status == 'APPROVED'
    return blocked('params_mismatch', status) unless body_placeholder_count(synced) == template.params.size

    Result.new(blocked: false, meta_status: status, last_synced_at: last_synced_at)
  end

  def body_placeholder_count(synced)
    body = Array(synced['components']).find { |component| component['type'].to_s.casecmp?('BODY') }
    body.to_h['text'].to_s.scan(PLACEHOLDER).flatten.uniq.size
  end

  def last_synced_at
    channel.message_templates_last_updated
  end

  def blocked(reason, meta_status = nil)
    Result.new(blocked: true, reason: reason, meta_status: meta_status, last_synced_at: last_synced_at)
  end
end
