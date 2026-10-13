# CT-03 / RF-13 / RF-18 / RF-37: the e-mails sent through the native quote
# inbox -- the quote request (rendered by ScanSolo::Quote::RequestEmail), the
# correction of an unreadable reply and the negotiation notification -- plus,
# for scansolo-proposta-aprovacao-email, the approval request (CT-05) and the
# proposal e-mail to the lead (CT-06).
# Pure: no writes, no I/O. Every text comes from `scan_solo.*` (RNF-08); the
# HTML keeps one label/field per line with `<br>` and escapes every value.
# Nothing secret (tokens, API URLs) is rendered (RNF-07, RNF-09): the only
# links are the Chatwoot conversation URL and the Propostas screen (CT-05);
# the lead e-mail has no link at all (the PDF goes attached).
class ScanSolo::Quote::EmailComposer
  Email = Struct.new(:subject, :text, :html, keyword_init: true)

  BLOCK_KEYS = %i[total_value schedule scope payment_terms notes].freeze

  class << self
    # CT-01 (RF-02..RF-13 of scansolo-solicitacao-orcamento-email, replacing
    # RF-13 here): rendered by ScanSolo::Quote::RequestEmail.
    def request(snapshot:)
      ScanSolo::Quote::RequestEmail.render(snapshot: snapshot).email
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

    # CT-05: posted in the quote request thread, whose `mail_subject` is the
    # e-mail subject. The lead e-mail warning mirrors the approval block (RF-08).
    def approval_request(proposal_version:)
      opportunity = proposal_version.proposal.opportunity
      number = proposal_version.proposal_number
      details = {
        number: number, version: proposal_version.version_number.to_s,
        value: current_value(amount: proposal_version.value, currency: proposal_version.currency), lead: lead_name(opportunity)
      }
      lines = [
        t('proposal.approval_request.intro'),
        '',
        *details.map { |key, value| line(t("proposal.approval_request.#{key}"), value) },
        *(t('proposal.approval_request.lead_email_missing') unless opportunity.lead_email_valid?),
        '',
        line(t('proposal.approval_request.link'), proposals_url(opportunity.account_id)),
        t('proposal.approval_request.approval_only_in_screen')
      ]

      build(t('proposal.approval_request.subject_suffix', proposal_number: number), lines)
    end

    # CT-06: the PDF goes attached, so the body carries no document link.
    def lead_proposal(proposal_version:)
      number = proposal_version.proposal_number
      lines = [
        t('proposal.lead_email.greeting', name: proposal_version.proposal.opportunity.contact.name),
        '',
        t('proposal.lead_email.body'),
        '',
        line(t('proposal.lead_email.number'), number),
        '',
        t('proposal.lead_email.closing')
      ]

      build(t('proposal.lead_email.subject', proposal_number: number), lines)
    end

    # The Chatwoot conversation link, also used by the CT-07 payload.
    def conversation_url(account_id, display_id)
      "#{ENV.fetch('FRONTEND_URL', nil)}/app/accounts/#{account_id}/conversations/#{display_id}"
    end

    # CT-05: the Propostas screen, the only place where a version is approved.
    def proposals_url(account_id)
      "#{ENV.fetch('FRONTEND_URL', nil)}/app/accounts/#{account_id}/scansolo/proposals"
    end

    # The empty CT-04 block, also used by the parser specs.
    def empty_block
      block_lines.join("\n")
    end

    # The CT-04 instructions and empty block that end every quote thread e-mail.
    def instruction_lines
      [t('quote.email.sections.instructions'), t('quote.email.instructions'), '', *block_lines]
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

    # RF-33 (c): an `empresa` `faltante` or `nao_informado` is absent.
    def lead_name(opportunity)
      company = opportunity.lead_state&.fields.to_h['empresa'].to_h
      [opportunity.contact.name, (company['value'] unless %w[faltante nao_informado].include?(company['status']))].compact_blank.join(' — ')
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
