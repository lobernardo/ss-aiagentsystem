# RF-47 / CT-05: the deterministic pt-BR "valor por extenso" sent to Make in
# `commercial.total_value_in_words` (never produced by AI). Pure function of a
# BigDecimal in 0,01..999.999.999,99; the words come from
# `scan_solo.amount_in_words.*`. Groups are joined with "e" when the following
# group is below one hundred or a round hundred ("doze mil e quinhentos"),
# otherwise with a comma ("um milhão, duzentos e trinta e quatro mil").
class ScanSolo::Quote::AmountInWords
  MAX_AMOUNT = BigDecimal('999999999.99')

  def self.call(amount)
    new(amount).call
  end

  def initialize(amount)
    raise ArgumentError, "amount must be a BigDecimal, got #{amount.class}" unless amount.is_a?(BigDecimal)

    @amount = amount.round(2)
    raise ArgumentError, "amount must be between 0.01 and #{MAX_AMOUNT.to_s('F')}" unless @amount.positive? && @amount <= MAX_AMOUNT
  end

  def call
    reais = amount.to_i
    centavos = ((amount - reais) * 100).to_i

    parts = []
    parts << reais_words(reais) if reais.positive?
    parts << "#{number_words(centavos)} #{plural(:cents, centavos)}" if centavos.positive?
    parts.join(" #{words[:connector]} ")
  end

  private

  attr_reader :amount

  def reais_words(reais)
    exact_millions = reais >= 1_000_000 && (reais % 1_000_000).zero?
    [number_words(reais), (words[:currency_preposition] if exact_millions), plural(:currency, reais)].compact.join(' ')
  end

  def number_words(number)
    groups = { million: number / 1_000_000, thousand: number / 1000 % 1000, units: number % 1000 }.reject { |_scale, value| value.zero? }

    groups.each_with_index.map do |(scale, value), index|
      separator = if index.zero?
                    ''
                  elsif value < 100 || (value % 100).zero?
                    " #{words[:connector]} "
                  else
                    ', '
                  end
      separator + group_words(scale, value)
    end.join
  end

  def group_words(scale, value)
    case scale
    when :million then "#{hundreds_words(value)} #{plural(:million, value)}"
    when :thousand then value == 1 ? words[:thousand] : "#{hundreds_words(value)} #{words[:thousand]}"
    else hundreds_words(value)
    end
  end

  def hundreds_words(value)
    return words[:one_hundred] if value == 100

    [words[:hundreds][value / 100], tens_words(value % 100)].compact_blank.join(" #{words[:connector]} ")
  end

  def tens_words(value)
    return words[:units][value] if value < 10
    return words[:teens][value - 10] if value < 20

    [words[:tens][value / 10], words[:units][value % 10]].compact_blank.join(" #{words[:connector]} ")
  end

  def plural(key, count)
    words[key][count == 1 ? :one : :other]
  end

  def words
    @words ||= I18n.t('scan_solo.amount_in_words')
  end
end
