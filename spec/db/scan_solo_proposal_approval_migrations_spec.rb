# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261007100002_allow_many_scan_solo_proposal_versions_per_quote_request.rb')
require Rails.root.join('db/migrate/20261007100003_add_unique_idempotency_key_to_scan_solo_make_requests.rb')

# T04: data-foundation migrations for proposal approval and e-mail delivery.
# DDL is transactional in PostgreSQL, so every migrate(:up)/(:down) below is
# rolled back with the example.
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'ScanSolo proposal approval migrations' do
  let(:connection) { ActiveRecord::Base.connection }
  let(:account) { create(:account) }
  let(:rejected_status) { 6 }

  def create_quote_request
    contact = create(:contact, account: account)
    conversation = create(:conversation, account: account, contact: contact)
    opportunity = ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation)
    quote_request = ScanSolo::QuoteRequest.create!(account: account, opportunity: opportunity, correlation_id: SecureRandom.uuid)
    [ScanSolo::Proposal.create!(opportunity: opportunity), quote_request]
  end

  def migrate(migration, direction)
    ActiveRecord::Migration.suppress_messages { migration.new.migrate(direction) }
  end

  describe '20261007100001 approval and e-mail delivery columns' do
    it 'adds the rejection, approval-request and notice columns to scan_solo_proposal_versions' do
      %i[
        rejected_at rejected_by_type rejected_by_id rejection_reason approval_requested_at
        approval_request_message_id notice_message_id notice_failure_reason artifact_sha256
      ].each do |column|
        expect(connection.column_exists?(:scan_solo_proposal_versions, column)).to be(true), "missing #{column}"
      end
      expect(connection.index_exists?(:scan_solo_proposal_versions, :notice_message_id)).to be true
    end

    it 'adds a unique email_conversation_id to scan_solo_proposals' do
      expect(connection.column_exists?(:scan_solo_proposals, :email_conversation_id)).to be true
      expect(connection.index_exists?(:scan_solo_proposals, :email_conversation_id, unique: true)).to be true
    end
  end

  describe '20261007100002 many proposal versions per quote request (RF-07, RF-26)' do
    it 'replaces the unique quote_request_id index with a non-unique one plus a partial unique index on open statuses' do
      indexes = connection.indexes(:scan_solo_proposal_versions)
      plain_index = indexes.find { |index| index.name == 'index_scan_solo_proposal_versions_on_quote_request_id' }
      open_index = indexes.find { |index| index.name == 'index_scan_solo_proposal_versions_one_open_per_quote_request' }

      expect(plain_index.unique).to be false
      expect(open_index.unique).to be true
      expect(open_index.columns).to eq(['quote_request_id'])
      expect(open_index.where).to eq('(status = ANY (ARRAY[0, 2, 5]))')
    end

    it 'accepts unlimited rejected versions but at most one non-terminal version per quote request' do
      proposal, quote_request = create_quote_request
      2.times do
        version = proposal.versions.create!(status: :generating, quote_request_id: quote_request.id)
        connection.execute("UPDATE scan_solo_proposal_versions SET status = #{rejected_status} WHERE id = #{version.id}")
      end
      proposal.versions.create!(status: :generating, quote_request_id: quote_request.id)

      expect(ScanSolo::ProposalVersion.where(quote_request_id: quote_request.id).count).to eq(3)
      expect { proposal.versions.create!(status: :approved, quote_request_id: quote_request.id) }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'keeps every existing version and status code when migrating up from one version per quote request' do
      migrate(AllowManyScanSoloProposalVersionsPerQuoteRequest, :down)
      %i[generated approved sent failed].each do |status|
        proposal, quote_request = create_quote_request
        proposal.versions.create!(status: status, quote_request_id: quote_request.id, approved_at: (Time.current if status == :approved))
      end
      snapshot = -> { ScanSolo::ProposalVersion.order(:id).pluck(:id, :status, :quote_request_id, :approved_at) }
      before_migration = snapshot.call

      migrate(AllowManyScanSoloProposalVersionsPerQuoteRequest, :up)

      expect(snapshot.call).to eq(before_migration)
      expect(before_migration.size).to eq(4)
    end
  end

  describe '20261007100003 unique idempotency_key on scan_solo_make_requests (RF-24)' do
    let(:migration) { AddUniqueIdempotencyKeyToScanSoloMakeRequests }

    def create_make_request(idempotency_key)
      ScanSolo::MakeRequest.create!(account: account, correlation_id: SecureRandom.uuid, idempotency_key: idempotency_key,
                                    action: 'proposal.generate', payload: {})
    end

    before { migrate(migration, :down) }

    it 'aborts listing every duplicated key without touching any record' do
      %w[dup-a dup-a dup-b dup-b unique-c].each { |key| create_make_request(key) }
      snapshot = -> { ScanSolo::MakeRequest.order(:id).pluck(:id, :idempotency_key, :status, :updated_at) }
      before_migration = snapshot.call

      expect { migrate(migration, :up) }
        .to raise_error(ActiveRecord::MigrationError, /duplicate idempotency_key: dup-a, dup-b$/)
      expect(snapshot.call).to eq(before_migration)
      expect(connection.index_exists?(:scan_solo_make_requests, :idempotency_key)).to be false
    end

    it 'adds the unique index when there are no duplicates' do
      create_make_request('key-1')
      create_make_request('key-2')

      migrate(migration, :up)

      expect(connection.index_exists?(:scan_solo_make_requests, :idempotency_key, unique: true)).to be true
      expect { create_make_request('key-1') }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  it 'never drops, renames or changes columns nor touches scan_solo_ai_agent_configs (RNF-05, RNF-07)' do
    Dir.glob(Rails.root.join('db/migrate/20261007*.rb')).each do |path|
      expect(File.read(path)).not_to match(/remove_column|rename_column|drop_table|change_column|scan_solo_ai_agent_configs/), path
    end
  end
end
# rubocop:enable RSpec/DescribeClass
