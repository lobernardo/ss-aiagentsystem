# frozen_string_literal: true

require 'rails_helper'

# T01: data foundation for the local proposal template (CT-06) and the
# qualification collection state (CT-10, RF-39). Inserts run inside the
# example transaction and are rolled back with it.
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'ScanSolo proposta template local migrations' do
  let(:connection) { ActiveRecord::Base.connection }
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }

  def insert_template(account_id, active:)
    now = Time.current
    connection.execute(
      ActiveRecord::Base.sanitize_sql_array(
        [
          'INSERT INTO scan_solo_proposal_templates (account_id, filename, byte_size, sha256, active, created_at, updated_at) ' \
          'VALUES (?, ?, ?, ?, ?, ?, ?)', account_id, 'proposta.docx', 1024, 'a' * 64, active, now, now
        ]
      )
    )
  end

  describe '20261013100001 scan_solo_proposal_templates (CT-06)' do
    it 'creates the table with the required columns, defaults and foreign keys' do
      %i[account_id filename byte_size sha256 active].each do |column|
        expect(connection.column_exists?(:scan_solo_proposal_templates, column, null: false)).to be(true), "missing not-null #{column}"
      end
      expect(connection.columns(:scan_solo_proposal_templates).find { |c| c.name == 'byte_size' }.sql_type).to eq('bigint')
      expect(connection.column_exists?(:scan_solo_proposal_templates, :active, :boolean, default: 'false')).to be true
      expect(connection.column_exists?(:scan_solo_proposal_templates, :uploaded_by_id, null: true)).to be true

      uploader_fk = connection.foreign_keys(:scan_solo_proposal_templates).find { |fk| fk.column == 'uploaded_by_id' }
      expect(uploader_fk.to_table).to eq('users')
      expect(uploader_fk.on_delete).to eq(:nullify)
      expect(connection.foreign_key_exists?(:scan_solo_proposal_templates, :accounts, column: :account_id)).to be true
    end

    it 'indexes (account_id, created_at)' do
      index = connection.indexes(:scan_solo_proposal_templates).find { |i| i.columns == %w[account_id created_at] }

      expect(index).to be_present
    end

    it 'rejects a second active template in the same account' do
      insert_template(account.id, active: true)

      expect { insert_template(account.id, active: true) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'accepts active templates in different accounts and many inactive templates in the same account' do
      insert_template(account.id, active: true)
      insert_template(other_account.id, active: true)
      insert_template(account.id, active: false)
      insert_template(account.id, active: false)

      expect(connection.select_value("SELECT COUNT(*) FROM scan_solo_proposal_templates WHERE account_id = #{account.id}")).to eq(3)
    end
  end

  describe '20261013100002 collection columns on scan_solo_lead_states (CT-10, RF-39)' do
    it 'adds nullable collection_offered_at and collection_mode without defaults' do
      expect(connection.column_exists?(:scan_solo_lead_states, :collection_offered_at, :datetime, null: true, default: nil)).to be true
      expect(connection.column_exists?(:scan_solo_lead_states, :collection_mode, :string, null: true, default: nil)).to be true
    end

    it 'reads nil for both columns on a lead state initialized without them' do
      contact = create(:contact, account: account)
      conversation = create(:conversation, account: account, contact: contact)
      opportunity = ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation)
      lead_state = opportunity.lead_state.reload

      expect(lead_state.collection_offered_at).to be_nil
      expect(lead_state.collection_mode).to be_nil
    end
  end

  it 'does not touch scan_solo_proposal_versions (RNF-08)' do
    Dir.glob(Rails.root.join('db/migrate/20261013*.rb')).each do |path|
      expect(File.read(path)).not_to include('scan_solo_proposal_versions'), path
    end
  end

  it 'never drops, renames or changes columns (RNF-08)' do
    Dir.glob(Rails.root.join('db/migrate/20261013*.rb')).each do |path|
      expect(File.read(path)).not_to match(/remove_column|rename_column|change_column|drop_table/), path
    end
  end
end
# rubocop:enable RSpec/DescribeClass
