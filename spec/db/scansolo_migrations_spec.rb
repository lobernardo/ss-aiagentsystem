# frozen_string_literal: true

require 'rails_helper'

# Cross-cutting migration hygiene checks rather than a spec for a single class.
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'ScanSolo migrations' do
  let(:destructive_pattern) { /\b(remove_column|change_column|rename_column|drop_table|remove_table|change_table)\b/ }

  let(:scansolo_migration_files) do
    Dir.glob(Rails.root.join('db/migrate/*scan_solo*.rb'))
  end

  it 'finds the conversation-extension and audit-event migrations' do
    basenames = scansolo_migration_files.map { |path| File.basename(path) }

    expect(basenames).to include(a_string_matching(/create_scan_solo_conversation_extensions/))
    expect(basenames).to include(a_string_matching(/create_scan_solo_audit_events/))
  end

  it 'finds the pipeline-opportunity and stage-event migrations' do
    basenames = scansolo_migration_files.map { |path| File.basename(path) }

    expect(basenames).to include(a_string_matching(/create_scan_solo_pipeline_opportunities/))
    expect(basenames).to include(a_string_matching(/create_scan_solo_pipeline_stage_events/))
  end

  it 'finds the ai-agent-config migration' do
    basenames = scansolo_migration_files.map { |path| File.basename(path) }

    expect(basenames).to include(a_string_matching(/create_scan_solo_ai_agent_configs/))
  end

  it 'contains only create_table/add_column statements, never a destructive change to a pre-existing table' do
    expect(scansolo_migration_files).not_to be_empty

    scansolo_migration_files.each do |path|
      source = File.read(path)

      expect(source).to match(/create_table|add_column|add_index/), "#{path} does not define an additive schema change"
      expect(source).not_to match(destructive_pattern), "#{path} contains a destructive schema change"
    end
  end

  it 'creates the scan_solo_conversation_extensions table additively' do
    connection = ActiveRecord::Base.connection

    expect(connection.table_exists?(:scan_solo_conversation_extensions)).to be true
    expect(connection.column_exists?(:scan_solo_conversation_extensions, :conversation_id)).to be true
    expect(connection.column_exists?(:scan_solo_conversation_extensions, :ai_control_state)).to be true
  end

  it 'creates the scan_solo_audit_events table additively with no update path' do
    connection = ActiveRecord::Base.connection

    expect(connection.table_exists?(:scan_solo_audit_events)).to be true
    expect(connection.column_exists?(:scan_solo_audit_events, :updated_at)).to be false
    %i[subject_type subject_id event_type correlation_id payload created_at].each do |column|
      expect(connection.column_exists?(:scan_solo_audit_events, column)).to be true
    end
  end

  it 'creates the scan_solo_pipeline_opportunities table additively' do
    connection = ActiveRecord::Base.connection

    expect(connection.table_exists?(:scan_solo_pipeline_opportunities)).to be true
    %i[account_id contact_id conversation_id owner_id stage last_customer_interaction_at].each do |column|
      expect(connection.column_exists?(:scan_solo_pipeline_opportunities, column)).to be true
    end
  end

  it 'creates the scan_solo_pipeline_stage_events table additively with no update path' do
    connection = ActiveRecord::Base.connection

    expect(connection.table_exists?(:scan_solo_pipeline_stage_events)).to be true
    expect(connection.column_exists?(:scan_solo_pipeline_stage_events, :updated_at)).to be false
    %i[opportunity_id from_stage to_stage actor_type actor_id created_at].each do |column|
      expect(connection.column_exists?(:scan_solo_pipeline_stage_events, column)).to be true
    end
  end

  it 'creates the scan_solo_ai_agent_configs table additively with a draft/published status and a self-reference' do
    connection = ActiveRecord::Base.connection

    expect(connection.table_exists?(:scan_solo_ai_agent_configs)).to be true
    %i[
      account_id status published_version_id name enabled model_provider model_selection role objective
      persona tone instructions service_rules qualification_playbook required_qualification_fields
      restricted_information forbidden_subjects transfer_criteria response_limits service_hours
    ].each do |column|
      expect(connection.column_exists?(:scan_solo_ai_agent_configs, column)).to be true
    end
  end

  it 'finds the knowledge-source and knowledge-chunk migrations' do
    basenames = scansolo_migration_files.map { |path| File.basename(path) }

    expect(basenames).to include(a_string_matching(/create_scan_solo_knowledge_sources/))
    expect(basenames).to include(a_string_matching(/create_scan_solo_knowledge_chunks/))
  end

  it 'creates the scan_solo_knowledge_sources table additively' do
    connection = ActiveRecord::Base.connection

    expect(connection.table_exists?(:scan_solo_knowledge_sources)).to be true
    %i[account_id added_by_id source_type title content origin enabled].each do |column|
      expect(connection.column_exists?(:scan_solo_knowledge_sources, column)).to be true
    end
  end

  it 'creates the scan_solo_knowledge_chunks table additively, with embedding using the existing vector column type' do
    connection = ActiveRecord::Base.connection

    expect(connection.table_exists?(:scan_solo_knowledge_chunks)).to be true
    %i[source_id content position embedding].each do |column|
      expect(connection.column_exists?(:scan_solo_knowledge_chunks, column)).to be true
    end

    embedding_column = connection.columns(:scan_solo_knowledge_chunks).find { |c| c.name == 'embedding' }
    expect(embedding_column.sql_type).to eq('vector(1536)')
  end

  it 'adds the embedding column via its own additive migration, not folded into the create_table migration' do
    embedding_migration = scansolo_migration_files.find { |path| path.include?('add_embedding_to_scan_solo_knowledge_chunks') }

    expect(embedding_migration).to be_present
    expect(File.read(embedding_migration)).to include('add_column')
  end
end
# rubocop:enable RSpec/DescribeClass
