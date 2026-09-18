# frozen_string_literal: true

require 'rails_helper'

# Cross-cutting migration hygiene checks rather than a spec for a single class.
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'ScanSolo migrations' do
  let(:destructive_pattern) { /\b(remove_column|change_column|rename_column|drop_table|remove_table|change_table)\b/ }

  let(:scansolo_migration_files) do
    Dir.glob(Rails.root.join('db/migrate/*_create_scan_solo_*.rb'))
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

  it 'contains only create_table statements, never a destructive change to a pre-existing table' do
    expect(scansolo_migration_files).not_to be_empty

    scansolo_migration_files.each do |path|
      source = File.read(path)

      expect(source).to include('create_table'), "#{path} does not define a table"
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
end
# rubocop:enable RSpec/DescribeClass
