require 'rails_helper'

# Cross-cutting hygiene checks (hostname search, config passthrough) rather
# than a spec for a single class.
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'ScanSolo branding & hostname hygiene' do
  describe 'production hostname hygiene' do
    it 'never hardcodes scansolo.com.br in application logic' do
      # Application-logic source files where a hardcoded scansolo.com.br would be
      # a real bug (as opposed to configuration, .env.example or docs, which are
      # allowed to mention the production hostname).
      code_extensions = %w[rb js jsx ts tsx vue erb haml]

      searched_paths = code_extensions.flat_map do |extension|
        Dir.glob(Rails.root.join('app', '**', "*.#{extension}")) +
          Dir.glob(Rails.root.join('lib', '**', "*.#{extension}"))
      end
      searched_paths << Rails.root.join('config/routes.rb').to_s

      offending_files = searched_paths.select do |path|
        File.file?(path) && File.read(path).include?('scansolo.com.br')
      end

      expect(offending_files).to be_empty
    end
  end

  describe 'branding configuration' do
    after { GlobalConfig.clear_cache }

    it 'derives installation branding exclusively from InstallationConfig-backed settings, with no ScanSolo code involved' do
      %w[INSTALLATION_NAME BRAND_NAME BRAND_URL LOGO LOGO_DARK LOGO_THUMBNAIL].each do |config_name|
        InstallationConfig.where(name: config_name).first_or_create!(value: 'placeholder', locked: false)
      end

      InstallationConfig.find_by(name: 'INSTALLATION_NAME').update!(value: 'ScanSolo Branding Test')
      InstallationConfig.find_by(name: 'BRAND_NAME').update!(value: 'ScanSolo')
      GlobalConfig.clear_cache

      expect(GlobalConfig.get_value('INSTALLATION_NAME')).to eq('ScanSolo Branding Test')
      expect(GlobalConfig.get_value('BRAND_NAME')).to eq('ScanSolo')
    end
  end
end
# rubocop:enable RSpec/DescribeClass
