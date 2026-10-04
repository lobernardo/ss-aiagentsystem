# CT-03 / RF-13 / RF-18 / RF-37: the e-mails sent through the native quote
# inbox -- the quote request, the correction of an unreadable reply and the
# negotiation notification. Pure: no writes, no I/O. Every text comes from
# `scan_solo.*` (RNF-08); the HTML keeps one label/field per line with `<br>`
# and escapes every value. Nothing secret (tokens, API URLs) is rendered: the
# only link is the Chatwoot conversation URL (RNF-07).
class ScanSolo::Quote::EmailComposer
  Email = Struct.new(:subject, :text, :html, keyword_init: true)

  BLOCK_KEYS = %i[total_value schedule scope payment_terms notes].freeze

  class << self
    # RF-13, in order: identification, every non-`faltante` catalog field
    # (`inferido` marked "(a confirmar)") and the empty CT-04 block.
    def request(opportunity:, projection:)
      company = projection.blocks.values.flatten.find { |field| field[:key] == 'empresa' && field[:status] != 'faltante' }&.dig(:value)
      lines = [
        t('quote.email.sections.identification'),
        *identification_lines(opportunity, company),
        '',
        t('quote.email.sections.collected_data'),
        *collected_lines(projection),
        '',
        *instruction_lines
      ]

      build(t('quote.email.subject', opportunity_id: opportunity.id, name: company.presence || opportunity.contact.name), lines)
    end

    # RF-18: posted in the request thread, so the subject is the thread's
    # `mail_subject` (native "Re:" prefix) and none is composed here.
    def correction(problems:)
      lines = [
        t('quote.correction.intro'),
        '',
        *problems.map { |key| t('quote.correction.field_problem', label: t("quote.block.labels.#{key}")) },
        '',
        *instruction_lines
      ]

      build(nil, lines)
    end

    # RF-37: the 9 items of the CT-07 payload, in their own thread.
    def negotiation(payload:)
      contact = payload[:contact]
      items = {
        name: contact[:name], company: contact[:company], phone: contact[:phone], opportunity: "##{payload[:opportunity_id]}",
        stage: stage_label(payload[:stage]), conversation_link: payload[:conversation_url], request_summary: payload[:request_summary],
        proposal: proposal_details(payload[:proposal]), current_value: current_value(payload[:current_value])
      }
      lines = [*items.map { |key, value| line(t("negotiation.email.labels.#{key}"), value) }, *recent_message_lines(payload[:recent_messages])]

      build(t('negotiation.email.subject', opportunity_id: payload[:opportunity_id], name: contact[:company].presence || contact[:name]), lines)
    end

    # The Chatwoot conversation link, also used by the CT-07 payload.
    def conversation_url(account_id, display_id)
      "#{ENV.fetch('FRONTEND_URL', nil)}/app/accounts/#{account_id}/conversations/#{display_id}"
    end

    # The empty CT-04 block, also used by the parser specs.
    def empty_block
      block_lines.join("\n")
    end

    private

    def build(subject, lines)
      Email.new(
        subject: subject,
        text: lines.join("\n"),
        html: lines.map { |text| ERB::Util.html_escape(text).gsub("\n", '<br>') }.join('<br>')
      )
    end

    def line(label, value)
      "#{label}: #{value.presence || t('quote.email.not_informed')}"
    end

    def identification_lines(opportunity, company)
      contact = opportunity.contact
      {
        opportunity: "##{opportunity.id}", name: contact.name, company: company, phone: contact.phone_number, email: contact.email,
        origin: t("quote.email.origin.#{opportunity.lead_source || 'none'}"), owner: opportunity.owner&.name,
        stage: stage_label(opportunity.stage),
        conversation_link: conversation_url(opportunity.account_id, opportunity.conversation.display_id)
      }.map { |key, value| line(t("quote.email.identification.#{key}"), value) }
    end

    def collected_lines(projection)
      projection.blocks.values.flatten.reject { |field| field[:status] == 'faltante' }.map do |field|
        value = field[:status] == 'inferido' ? "#{field[:value]} #{t('quote.email.to_confirm')}" : field[:value].to_s
        line(field[:label], value)
      end
    end

    def instruction_lines
      [t('quote.email.sections.instructions'), t('quote.email.instructions'), '', *block_lines]
    end

    def block_lines
      [t('quote.block.start'), *BLOCK_KEYS.map { |key| "#{t("quote.block.labels.#{key}")}:" }, t('quote.block.end')]
    end

    def proposal_details(proposal)
      return t('negotiation.email.no_proposal') if proposal.nil?

      t('negotiation.email.proposal_details', **proposal.slice(:version_number, :proposal_number, :status, :document_url))
    end

    def current_value(value)
      return t('negotiation.email.no_proposal') if value.nil?

      amount = ActiveSupport::NumberHelper.number_to_delimited(format('%.2f', value[:amount]), delimiter: '.', separator: ',')
      "#{value[:currency]} #{amount}"
    end

    def recent_message_lines(messages)
      ["#{t('negotiation.email.labels.recent_messages')}:", *messages.map do |message|
        sent_at = Time.zone.parse(message[:created_at].to_s).strftime('%d/%m/%Y %H:%M')
        "[#{sent_at}] #{t("negotiation.email.senders.#{message[:sender]}")}: #{message[:content]}"
      end]
    end

    def stage_label(stage)
      ScanSolo::Handoff::HandoffService::STAGE_LABELS.fetch(stage.to_s)
    end

    def t(key, **)
      I18n.t("scan_solo.#{key}", **)
    end
  end
end
