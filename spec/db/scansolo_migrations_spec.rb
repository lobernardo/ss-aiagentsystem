# frozen_string_literal: true

require 'rails_helper'

# Cross-cutting migration hygiene checks rather than a spec for a single class.
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'ScanSolo migrations' do
  let(:destructive_pattern) { /\b(remove_column|change_column|rename_column|drop_table|remove_table|change_table)\b/ }

  let(:scansolo_migration_files) do
    Dir.glob(Rails.root.join('db/migrate/*{scan_solo,scansolo}*.rb'))
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

      expect(source).to match(/create_table|add_column|add_index|add_reference/), "#{path} does not define an additive schema change"
      expect(source).not_to match(destructive_pattern), "#{path} contains a destructive schema change"
    end
  end

  it 'finds the scansolo_enabled account-flag migration (T01) alongside every scan_solo_* table migration' do
    basenames = scansolo_migration_files.map { |path| File.basename(path) }

    expect(basenames).to include(a_string_matching(/add_scansolo_enabled_flag_to_accounts/))
    # T79: the consolidated additive-only check above (and the destructive-pattern
    # check) must also cover this migration, since it is the one ScanSolo migration
    # that touches a pre-existing Community table (accounts) rather than creating a
    # new scan_solo_* table -- RF-95/RNF-04 apply to it exactly the same way.
    expect(scansolo_migration_files.length).to eq(28)
  end

  it 'adds the account scansolo_feature_flags column additively, never modifying a pre-existing accounts column' do
    connection = ActiveRecord::Base.connection

    account_flag_migration = scansolo_migration_files.find { |path| path.include?('add_scansolo_enabled_flag_to_accounts') }
    expect(account_flag_migration).to be_present

    source = File.read(account_flag_migration)
    expect(source).to match(/add_column\s+:accounts,\s*:scansolo_feature_flags/)
    expect(source).not_to match(destructive_pattern)

    expect(connection.column_exists?(:accounts, :scansolo_feature_flags)).to be true
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

  it 'finds the ai-turns telemetry migration' do
    basenames = scansolo_migration_files.map { |path| File.basename(path) }

    expect(basenames).to include(a_string_matching(/create_scan_solo_ai_turns/))
  end

  it 'creates the scan_solo_ai_turns table additively with a unique index on message_id and correlation_id' do
    connection = ActiveRecord::Base.connection

    expect(connection.table_exists?(:scan_solo_ai_turns)).to be true
    %i[
      message_id conversation_id correlation_id invocation_status model_provider model_reference input_tokens
      output_tokens cost_estimate latency_ms failure_reason context_snapshot guardrail_outcome
      knowledge_evidence action_evidence
    ].each do |column|
      expect(connection.column_exists?(:scan_solo_ai_turns, column)).to be true
    end

    indexes = connection.indexes(:scan_solo_ai_turns)
    message_id_index = indexes.find { |index| index.columns == ['message_id'] }
    correlation_id_index = indexes.find { |index| index.columns == ['correlation_id'] }

    expect(message_id_index).to be_present
    expect(message_id_index.unique).to be true
    expect(correlation_id_index).to be_present
    expect(correlation_id_index.unique).to be true
  end

  it 'adds the response_message reference via its own additive migration' do
    connection = ActiveRecord::Base.connection

    expect(connection.column_exists?(:scan_solo_ai_turns, :response_message_id)).to be true

    response_migration = scansolo_migration_files.find { |path| path.include?('add_response_message_reference_to_scan_solo_ai_turns') }
    expect(response_migration).to be_present
    expect(File.read(response_migration)).to include('add_reference')
  end

  it 'finds the agent-action and agent-action-execution migrations' do
    basenames = scansolo_migration_files.map { |path| File.basename(path) }

    expect(basenames).to include(a_string_matching(/create_scan_solo_agent_actions/))
    expect(basenames).to include(a_string_matching(/create_scan_solo_agent_action_executions/))
  end

  it 'creates the scan_solo_agent_actions table additively with a unique index on action_id' do
    connection = ActiveRecord::Base.connection

    expect(connection.table_exists?(:scan_solo_agent_actions)).to be true
    %i[action_id classification schema].each do |column|
      expect(connection.column_exists?(:scan_solo_agent_actions, column)).to be true
    end

    action_id_index = connection.indexes(:scan_solo_agent_actions).find { |index| index.columns == ['action_id'] }
    expect(action_id_index).to be_present
    expect(action_id_index.unique).to be true
  end

  it 'creates the scan_solo_agent_action_executions table additively with a unique index on idempotency_key' do
    connection = ActiveRecord::Base.connection

    expect(connection.table_exists?(:scan_solo_agent_action_executions)).to be true
    %i[action_id turn_id correlation_id idempotency_key params status confirmed_at audit_event_id].each do |column|
      expect(connection.column_exists?(:scan_solo_agent_action_executions, column)).to be true
    end

    idempotency_index = connection.indexes(:scan_solo_agent_action_executions).find { |index| index.columns == ['idempotency_key'] }
    expect(idempotency_index).to be_present
    expect(idempotency_index.unique).to be true
  end

  it 'finds the cadence-definition, cadence-enrollment and cadence-attempt migrations' do
    basenames = scansolo_migration_files.map { |path| File.basename(path) }

    expect(basenames).to include(a_string_matching(/create_scan_solo_cadence_definitions/))
    expect(basenames).to include(a_string_matching(/create_scan_solo_cadence_enrollments/))
    expect(basenames).to include(a_string_matching(/create_scan_solo_cadence_attempts/))
  end

  it 'creates the scan_solo_cadence_definitions table additively' do
    connection = ActiveRecord::Base.connection

    expect(connection.table_exists?(:scan_solo_cadence_definitions)).to be true
    %i[stage version offsets active].each do |column|
      expect(connection.column_exists?(:scan_solo_cadence_definitions, column)).to be true
    end
  end

  it 'creates the scan_solo_cadence_enrollments table additively with a unique index on (opportunity_id, cadence_definition_id)' do
    connection = ActiveRecord::Base.connection

    expect(connection.table_exists?(:scan_solo_cadence_enrollments)).to be true
    %i[opportunity_id cadence_definition_id status current_step next_attempt_at paused_at].each do |column|
      expect(connection.column_exists?(:scan_solo_cadence_enrollments, column)).to be true
    end

    opportunity_definition_index = connection.indexes(:scan_solo_cadence_enrollments)
                                             .find { |index| index.columns.sort == %w[cadence_definition_id opportunity_id] }
    expect(opportunity_definition_index).to be_present
    expect(opportunity_definition_index.unique).to be true
  end

  it 'creates the scan_solo_cadence_attempts table additively with a unique index on (enrollment_id, step)' do
    connection = ActiveRecord::Base.connection

    expect(connection.table_exists?(:scan_solo_cadence_attempts)).to be true
    %i[enrollment_id step cadence_version template_reference scheduled_at sent_at result].each do |column|
      expect(connection.column_exists?(:scan_solo_cadence_attempts, column)).to be true
    end

    step_index = connection.indexes(:scan_solo_cadence_attempts).find { |index| index.columns.sort == %w[enrollment_id step] }
    expect(step_index).to be_present
    expect(step_index.unique).to be true
  end

  it 'finds the proposal and proposal-version migrations' do
    basenames = scansolo_migration_files.map { |path| File.basename(path) }

    expect(basenames).to include(a_string_matching(/create_scan_solo_proposals/))
    expect(basenames).to include(a_string_matching(/create_scan_solo_proposal_versions/))
  end

  it 'creates the scan_solo_proposals table additively with a unique index on opportunity_id' do
    connection = ActiveRecord::Base.connection

    expect(connection.table_exists?(:scan_solo_proposals)).to be true
    %i[opportunity_id current_version_id].each do |column|
      expect(connection.column_exists?(:scan_solo_proposals, column)).to be true
    end

    opportunity_index = connection.indexes(:scan_solo_proposals).find { |index| index.columns == ['opportunity_id'] }
    expect(opportunity_index).to be_present
    expect(opportunity_index.unique).to be true
  end

  it 'creates the scan_solo_proposal_versions table additively with every expected column' do
    connection = ActiveRecord::Base.connection

    expect(connection.table_exists?(:scan_solo_proposal_versions)).to be true
    %i[
      proposal_id version_number status is_current value currency artifact_url failure_reason
      generate_correlation_id generate_requested_at generate_callback_applied_at
      approved_at approved_by_type approved_by_id
      send_correlation_id send_requested_at send_callback_applied_at sent_message_id
    ].each do |column|
      expect(connection.column_exists?(:scan_solo_proposal_versions, column)).to be true
    end
  end

  it 'enforces a single current version per proposal via a partial unique index' do
    connection = ActiveRecord::Base.connection

    current_index = connection.indexes(:scan_solo_proposal_versions).find { |index| index.name == 'index_scan_solo_proposal_versions_on_current' }
    expect(current_index).to be_present
    expect(current_index.unique).to be true
    expect(current_index.where).to eq('(is_current = true)')
  end

  it 'enforces unique generate/send correlation ids on scan_solo_proposal_versions' do
    connection = ActiveRecord::Base.connection

    generate_correlation_index = connection.indexes(:scan_solo_proposal_versions).find { |index| index.columns == ['generate_correlation_id'] }
    expect(generate_correlation_index).to be_present
    expect(generate_correlation_index.unique).to be true

    send_correlation_index = connection.indexes(:scan_solo_proposal_versions).find { |index| index.columns == ['send_correlation_id'] }
    expect(send_correlation_index).to be_present
    expect(send_correlation_index.unique).to be true
  end

  it 'finds the require_proposal_approval addition to scan_solo_ai_agent_configs' do
    connection = ActiveRecord::Base.connection

    basenames = scansolo_migration_files.map { |path| File.basename(path) }
    expect(basenames).to include(a_string_matching(/add_require_proposal_approval_to_scan_solo_ai_agent_configs/))
    expect(connection.column_exists?(:scan_solo_ai_agent_configs, :require_proposal_approval)).to be true
  end

  it 'finds the make-request and make-callback migrations' do
    basenames = scansolo_migration_files.map { |path| File.basename(path) }

    expect(basenames).to include(a_string_matching(/create_scan_solo_make_requests/))
    expect(basenames).to include(a_string_matching(/create_scan_solo_make_callbacks/))
  end

  it 'creates the scan_solo_make_requests table additively with a unique index on correlation_id' do
    connection = ActiveRecord::Base.connection

    expect(connection.table_exists?(:scan_solo_make_requests)).to be true
    %i[account_id correlation_id idempotency_key action payload status retry_count].each do |column|
      expect(connection.column_exists?(:scan_solo_make_requests, column)).to be true
    end

    correlation_index = connection.indexes(:scan_solo_make_requests).find { |index| index.columns == ['correlation_id'] }
    expect(correlation_index).to be_present
    expect(correlation_index.unique).to be true
  end

  it 'creates the scan_solo_make_callbacks table additively with a partial unique index on applied correlation_id (RF-39)' do
    connection = ActiveRecord::Base.connection

    expect(connection.table_exists?(:scan_solo_make_callbacks)).to be true
    expect(connection.column_exists?(:scan_solo_make_callbacks, :updated_at)).to be false
    %i[correlation_id action signature_valid applied rejection_reason payload created_at].each do |column|
      expect(connection.column_exists?(:scan_solo_make_callbacks, column)).to be true
    end

    correlation_index = connection.indexes(:scan_solo_make_callbacks).find { |index| index.columns == ['correlation_id'] }
    expect(correlation_index).to be_present
    expect(correlation_index.unique).to be true
    expect(correlation_index.where).to eq('(applied = true)')
    expect(connection.column_exists?(:scan_solo_make_callbacks, :expires_at)).to be false
  end

  it 'limits index replacements to the two reversible production migrations' do
    replacements = scansolo_migration_files.select { |path| File.read(path).match?(/\bremove_index\b/) }
    expect(replacements.map { |path| File.basename(path) }).to contain_exactly(
      '20260923000006_replace_scan_solo_cadence_enrollment_unique_index.rb',
      '20260923000007_replace_scan_solo_make_callbacks_correlation_index.rb'
    )
    replacements.each do |path|
      expect(File.read(path)).to include('def up', 'def down', 'add_index', 'where:')
    end
    scansolo_migration_files.each do |path|
      expect(File.read(path)).not_to match(/\b(?:delete|destroy)\b/i)
    end
  end

  it 'records the production columns, defaults and partial predicates in the schema' do
    schema = Rails.root.join('db/schema.rb').read
    expect(schema).to include('t.jsonb "allowed_inbox_ids", default: [], null: false')
    expect(schema).to include('t.jsonb "opt_out_keywords", default: ["PARAR", "SAIR", "STOP"], null: false')
    expect(schema).to include('create_table "scan_solo_contact_extensions"', 'create_table "scan_solo_template_mappings"')
    expect(schema).to include('nulls_not_distinct: true', 'where: "(applied = true)"')
    expect(schema).to match(/idx_scansolo_cadence_enrollments_on_opportunity_and_definition.*where:.*status.*0.*1/)
    %w[message_id last_block_reason last_checked_at external_error].each do |column|
      expect(ActiveRecord::Base.connection.column_exists?(:scan_solo_cadence_attempts, column)).to be true
    end
    %w[index_status index_error indexed_at chunk_count].each do |column|
      expect(ActiveRecord::Base.connection.column_exists?(:scan_solo_knowledge_sources, column)).to be true
    end
  end
end
# rubocop:enable RSpec/DescribeClass
