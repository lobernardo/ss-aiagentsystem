# Escalação comercial RF-01/RF-07/RF-08/RF-20/RF-22: the shared commercial
# contact rules. E164_PHONE_REGEXP is the single server rule for phone numbers
# (lead creation and the published commercial WhatsApp number).
# INTERNAL_NAME_PATTERN matches the internal contact name that must never reach
# the lead; `internal_name?` ignores case and accents.
module ScanSolo::Commercial::Rules
  E164_PHONE_REGEXP = /\A\+[1-9]\d{1,14}\z/
  INTERNAL_NAME_PATTERN = /luciano/i

  def self.internal_name?(text)
    I18n.transliterate(text.to_s).match?(INTERNAL_NAME_PATTERN)
  end
end
