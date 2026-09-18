require 'rails_helper'
require 'open3'

# Documentation/config-lint checks for the ScanSolo deployment topology
# (RF-93/RF-94) rather than a spec for a single class.
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'ScanSolo deployment documentation' do
  let(:doc_path) { Rails.root.join('docs/architecture/SCANSOLO_DEPLOYMENT.md') }
  let(:compose_path) { Rails.root.join('docker-compose.scansolo.yaml') }

  describe 'documented files exist' do
    it 'has the deployment documentation file' do
      expect(File.exist?(doc_path)).to be(true)
    end

    it 'has the additive ScanSolo docker compose file' do
      expect(File.exist?(compose_path)).to be(true)
    end
  end

  describe 'deployment documentation content' do
    let(:content) { File.read(doc_path) }

    it 'documents every required topology component' do
      %w[
        Sidekiq
        PostgreSQL
        Redis
        storage
        reverse
        TLS
        Health
        volumes
        Migrations
        restart
        Backup
        variables
        rotation
        Rollback
      ].each do |keyword|
        expect(content).to include(keyword), "expected documentation to mention #{keyword}"
      end
    end

    it 'states that no real deploy, DNS cutover, or provider activation occurs' do
      expect(content).to match(/no\s+.*?(?:actual|real)\s+production\s+deploy/im)
    end
  end

  describe 'docker compose config lint', if: system('which docker > /dev/null 2>&1') do
    it 'validates the base compose file plus the ScanSolo overlay without error' do
      base_compose = Rails.root.join('docker-compose.yaml')

      output, status = Open3.capture2e(
        'docker', 'compose', '-f', base_compose.to_s, '-f', compose_path.to_s, 'config',
        chdir: Rails.root.to_s
      )

      expect(status.success?).to be(true), "docker compose config failed:\n#{output}"
    end
  end
end
# rubocop:enable RSpec/DescribeClass
