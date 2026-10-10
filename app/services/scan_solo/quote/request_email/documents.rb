# RF-13 / RNF-03: the DOCUMENTAÇÃO RECEBIDA lines and the attachments of the
# e-mail. In order of receipt, a candidate is attached while the running total
# stays ≤ 15 MiB; the first one that would exceed it, every later one and the
# non-candidates (already sent, CT-03) are listed with the conversation link.
# `candidate_ids` nil = every attachment. Pure: nothing is downloaded.
class ScanSolo::Quote::RequestEmail::Documents
  LIMIT = 15 * 1024 * 1024

  Result = Struct.new(:lines, :attached_ids, keyword_init: true)

  def self.call(attachments:, candidate_ids:, conversation_url:)
    total = 0
    candidates = attachments.select { |attachment| candidate_ids.nil? || candidate_ids.include?(attachment['id']) }
    attached_ids = candidates.take_while { |attachment| (total += attachment['byte_size']) <= LIMIT }.pluck('id')
    lines = attachments.map do |attachment|
      details = { name: attachment['name'], type: attachment['type'] }
      attached_ids.include?(attachment['id']) ? t('attachment_attached', **details) : t('attachment_linked', **details, link: conversation_url)
    end

    Result.new(lines: lines.presence || [t('no_documents')], attached_ids: attached_ids)
  end

  def self.t(key, **)
    I18n.t("scan_solo.quote.request_email.#{key}", **)
  end
  private_class_method :t
end
