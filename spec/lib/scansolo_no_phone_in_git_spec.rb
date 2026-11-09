require 'rails_helper'

# RNF-01: no real phone number in the files of the commercial wa.me
# escalation. Only the fictitious +5511999999999 may appear.
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'ScanSolo commercial escalation phone numbers in Git' do
  phone_pattern = /(?<!\d)(?:\+?55[\s.-]?)?\(?[1-9]{2}\)?[\s.-]?9?\d{4}[\s.-]?\d{4}(?!\d)/
  fictitious_digits = %w[5511999999999 11999999999].freeze

  feature_files = %w[
    app/services/scan_solo/commercial/**/*.rb
    app/services/scan_solo/actions/escalate_to_commercial_action.rb
    db/migrate/*_add_commercial_whatsapp_number_to_scan_solo_ai_agent_configs.rb
    db/migrate/*_add_commercial_escalation_to_scan_solo_pipeline_opportunities.rb
    app/javascript/dashboard/i18n/locale/en/scansolo.json
    spec/services/scan_solo/commercial/**/*_spec.rb
    spec/services/scan_solo/actions/escalate_to_commercial_action_spec.rb
    spec/integration/scan_solo/escalacao_comercial_wame_spec.rb
  ].flat_map { |pattern| Dir[Rails.root.join(pattern)] }

  real_phones = lambda do |text|
    text.to_enum(:scan, phone_pattern).map { Regexp.last_match(0) }.reject { |match| fictitious_digits.include?(match.gsub(/\D/, '')) }
  end

  it 'scans every feature file' do
    expect(feature_files.size).to be >= 12
  end

  it 'has no real phone in the feature files' do
    offenders = feature_files.index_with { |file| real_phones.call(File.read(file)) }.reject { |_, phones| phones.empty? }

    expect(offenders).to be_empty
  end

  it 'has no real phone in the scan_solo scope of en.yml' do
    scope = YAML.load_file(Rails.root.join('config/locales/en.yml')).dig('en', 'scan_solo')

    expect(real_phones.call(scope.to_json)).to be_empty
  end

  it 'flags a real phone and lets the fictitious one through' do
    expect(real_phones.call('fale no (21) 97777-6666 ou https://wa.me/5511999999999')).to eq(['(21) 97777-6666'])
  end
end
# rubocop:enable RSpec/DescribeClass
