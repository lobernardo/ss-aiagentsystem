# RF-16 (b): deterministic opt-out keyword check -- never a model call. A
# message matches only when its whole text equals a configured keyword once
# both sides are normalized (surrounding whitespace trimmed, accents and
# punctuation stripped, case ignored), so `Parar!` matches `PARAR` while a
# phrase merely containing the keyword is left to the model's intent
# detection (`cadence_signal` opt_out).
class ScanSolo::OptOut::KeywordMatcher
  def self.match?(content, keywords)
    normalized_content = normalize(content)
    return false if normalized_content.empty?

    Array(keywords).any? { |keyword| normalize(keyword) == normalized_content }
  end

  def self.normalize(text)
    I18n.transliterate(text.to_s).downcase.gsub(/[[:punct:]]/, '').squish
  end
end
