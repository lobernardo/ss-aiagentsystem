# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261010100001_add_quote_email_validation_mode_to_scan_solo_ai_agent_configs.rb')

# T01: data foundation for the quote request e-mail redesign. DDL is
# transactional in PostgreSQL, so every migrate(:up)/(:down) below is rolled
# back with the example.
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'ScanSolo quote request e-mail migrations' do
  let(:connection) { ActiveRecord::Base.connection }
  let(:account) { create(:account) }

  def migrate(migration, direction)
    ActiveRecord::Migration.suppress_messages { migration.new.migrate(direction) }
    ScanSolo::AiAgentConfig.reset_column_information
  end

  describe '20261010100001 quote_email_validation_mode on scan_solo_ai_agent_configs (RF-21, CT-05)' do
    let(:migration) { AddQuoteEmailValidationModeToScanSoloAiAgentConfigs }
    let(:preserved_fields) { ScanSolo::AiAgentConfig::FIELDS - [:quote_email_validation_mode] }

    after { ScanSolo::AiAgentConfig.reset_column_information }

    it 'turns the flag on for pre-existing draft and published configs without changing any other field' do
      migrate(migration, :down)
      draft = ScanSolo::AiAgentConfig.draft_for!(account)
      draft.update!(name: 'Agente', enabled: true, require_proposal_approval: false, opt_out_keywords: ['SAIR'],
                    required_qualification_fields: [{ 'key' => 'cidade', 'label' => 'Cidade' }],
                    quote_recipient_email: 'luciano@example.com')
      published = ScanSolo::AiAgentConfig.create!(draft.slice(*preserved_fields).merge(account: account, status: :published))
      draft.update!(published_version: published)
      snapshot = -> { ScanSolo::AiAgentConfig.where(account: account).order(:id).map { |config| config.slice(*preserved_fields) } }
      before_migration = snapshot.call

      migrate(migration, :up)

      expect(ScanSolo::AiAgentConfig.where(account: account).pluck(:status, :quote_email_validation_mode))
        .to contain_exactly(['draft', true], ['published', true])
      expect(snapshot.call).to eq(before_migration)
    end
  end

  describe '20261010100002 rendered snapshot, update window and scan_solo_quote_request_updates (RF-14, RNF-05)' do
    let(:quote_request) do
      contact = create(:contact, account: account)
      conversation = create(:conversation, account: account, contact: contact)
      opportunity = ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation)
      ScanSolo::QuoteRequest.create!(account: account, opportunity: opportunity, correlation_id: SecureRandom.uuid)
    end

    def insert_update(version_digest)
      now = Time.current
      connection.execute(
        ActiveRecord::Base.sanitize_sql_array(
          [
            'INSERT INTO scan_solo_quote_request_updates (account_id, quote_request_id, version_digest, created_at, updated_at) ' \
            'VALUES (?, ?, ?, ?, ?)', account.id, quote_request.id, version_digest, now, now
          ]
        )
      )
    end

    it 'adds nullable rendered_snapshot, rendered_digest and update_window_ends_at to scan_solo_quote_requests' do
      { rendered_snapshot: :jsonb, rendered_digest: :string, update_window_ends_at: :datetime }.each do |column, type|
        expect(connection.column_exists?(:scan_solo_quote_requests, column, type, null: true)).to be(true), "missing #{column}"
      end
    end

    it 'creates scan_solo_quote_request_updates with a quote request foreign key' do
      %i[account_id quote_request_id version_digest message_id sent_at created_at updated_at].each do |column|
        expect(connection.column_exists?(:scan_solo_quote_request_updates, column)).to be(true), "missing #{column}"
      end
      expect(connection.column_exists?(:scan_solo_quote_request_updates, :version_digest, :string, null: false)).to be true
      expect(connection.foreign_key_exists?(:scan_solo_quote_request_updates, :scan_solo_quote_requests, column: :quote_request_id)).to be true
    end

    it 'allows at most one update per (quote_request_id, version_digest)' do
      insert_update('digest-a')
      insert_update('digest-b')

      expect { insert_update('digest-a') }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  it 'never drops, renames or changes columns (OC/RNF-05)' do
    Dir.glob(Rails.root.join('db/migrate/20261010*.rb')).each do |path|
      expect(File.read(path)).not_to match(/remove_column|rename_column|change_column|drop_table/), path
    end
  end
end
# rubocop:enable RSpec/DescribeClass
