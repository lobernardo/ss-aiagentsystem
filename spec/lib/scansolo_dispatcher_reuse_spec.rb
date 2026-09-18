require 'rails_helper'

# Cross-cutting hygiene check rather than a spec for a single class: confirms
# every ScanSolo domain event flows through the existing Dispatcher/AsyncDispatcher
# seam (RF-96) instead of a new pub/sub mechanism, and that the high-risk
# upstream customizations are documented (RF-97).
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'ScanSolo Dispatcher reuse' do
  describe 'no parallel pub/sub mechanism' do
    it 'defines no event-bus/pub-sub primitive under app/**/scan_solo/** or lib/**/scan_solo/**' do
      pubsub_class_pattern = /class\s+\S*(Bus|Emitter|Broadcaster|PubSub|EventBus|MessageBus)\b/

      searched_paths = Dir.glob(Rails.root.join('app/**/scan_solo/**/*.rb')) +
                       Dir.glob(Rails.root.join('lib/**/scan_solo/**/*.rb'))

      expect(searched_paths).not_to be_empty

      offending_files = searched_paths.select do |path|
        File.read(path).match?(pubsub_class_pattern)
      end

      expect(offending_files).to be_empty
    end
  end

  describe 'native dispatcher registration' do
    it 'registers ScanSolo::ConversationListener as a BaseListener on AsyncDispatcher' do
      expect(ScanSolo::ConversationListener.ancestors).to include(BaseListener)
      expect(AsyncDispatcher.new.listeners).to include(ScanSolo::ConversationListener.instance)
    end

    it 'enqueues the AI turn via the standard ActiveJob/Sidekiq queue, not a bespoke worker loop' do
      expect(ScanSolo::AiTurnJob.ancestors).to include(ActiveJob::Base)
    end
  end

  describe 'high-risk customization documentation (RF-97)' do
    let(:doc_path) { Rails.root.join('docs/architecture/SCANSOLO_UPSTREAM_RISK.md') }
    let(:doc_content) { File.read(doc_path) }

    it 'exists' do
      expect(File.exist?(doc_path)).to be true
    end

    it 'lists config/routes.rb as a documented high-risk customization' do
      expect(doc_content).to include('config/routes.rb')
    end

    it 'lists the Account scansolo_feature_flags addition as a documented high-risk customization' do
      expect(doc_content).to include('app/models/account.rb')
      expect(doc_content).to include('scansolo_feature_flags')
    end
  end
end
# rubocop:enable RSpec/DescribeClass
