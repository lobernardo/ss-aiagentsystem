# frozen_string_literal: true

require 'rake'
require 'rails_helper'

RSpec.describe Rake::Task do # rubocop:disable RSpec/SpecFilePathFormat
  describe 'scansolo:load_cadence_definitions' do
    subject(:task) { described_class['scansolo:load_cadence_definitions'] }

    before { task.reenable }

    it 'loads exactly the 4 active RF-25 definitions when run twice on an empty database' do
      expect do
        task.invoke
        task.reenable
        task.invoke
      end.to output(/novo_lead v1: \[2, 24, 48, 96\]/).to_stdout

      expect(ScanSolo::CadenceDefinition.active.order(:stage).pluck(:stage, :offsets)).to eq(
        [
          ['em_contato', [24, 48, 72, 96, 120]],
          ['em_qualificacao', [24, 48, 96, 168]],
          ['novo_lead', [2, 24, 48, 96]],
          ['proposta_enviada', [24, 72, 168]]
        ]
      )
    end
  end

  describe 'scansolo:backfill_lead_states' do
    subject(:task) { described_class['scansolo:backfill_lead_states'] }

    let(:account) { create(:account) }
    let(:ana) { create(:contact, account: account, name: 'Ana', email: nil, phone_number: nil, custom_attributes: { 'area' => '800 m²' }) }
    let(:opportunities) do
      %w[novo_lead em_contato em_qualificacao qualificado proposta_enviada negociacao ganho perdido].index_with do |stage|
        contact = stage == 'negociacao' ? ana : create(:contact, account: account)
        conversation = create(:conversation, account: account, contact: contact)
        ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: stage)
      end
    end
    let(:backfilled_at) { Time.zone.parse('2026-09-29 12:00:00') }

    def run_task
      task.reenable
      travel_to(backfilled_at) { task.invoke }
    end

    # Opportunities that existed before the lead state table.
    before do
      opportunities
      ScanSolo::LeadStateEvent.delete_all
      ScanSolo::LeadState.delete_all
    end

    it 'creates exactly one seeded lead state per opportunity, never confirmado (RF-01a)' do
      expect { run_task }.to output("Lead states created: 8\n").to_stdout

      states = opportunities.values.map { |opportunity| ScanSolo::LeadState.where(opportunity_id: opportunity.id).sole }
      expect(states.flat_map { |state| state.fields.values }.pluck('status')).not_to include('confirmado')
      expect(states).to all(satisfy { |state| state.fields.size == 34 })
    end

    it 'concludes the states at or past qualificado from the stage alone, without stage or audit events' do
      expect { run_task }.to output.to_stdout
                                   .and(not_change(ScanSolo::PipelineStageEvent, :count))
                                   .and(not_change(ScanSolo::AuditEvent, :count))

      negotiation = opportunities['negociacao'].reload
      expect(negotiation.lead_state).to have_attributes(qualification_status: 'concluida', qualification_completed_at: backfilled_at,
                                                        next_action: 'aguardar_cliente', next_action_source_message_id: nil)
      expect(negotiation.lead_state.fields['nome']).to include('value' => 'Ana', 'status' => 'inferido')
      expect(negotiation.stage).to eq('negociacao')
      expect(opportunities.slice('qualificado', 'proposta_enviada', 'ganho', 'perdido').values.map { |opportunity| opportunity.reload.lead_state })
        .to all(be_concluida)
      opportunities.slice('novo_lead', 'em_contato', 'em_qualificacao').each_value do |opportunity|
        expect(opportunity.reload.lead_state).to have_attributes(qualification_status: 'em_andamento', next_action: nil)
      end
    end

    it 'creates nothing and changes no state or event on a second run, and never writes to contacts' do
      expect { run_task }.to output.to_stdout
      snapshot = -> { [ScanSolo::LeadState.order(:id).map(&:attributes), ScanSolo::LeadStateEvent.order(:id).map(&:attributes)] }
      before_second_run = snapshot.call

      expect { run_task }.to output("Lead states created: 0\n").to_stdout
      expect(snapshot.call).to eq(before_second_run)
      expect(ana.reload.custom_attributes).to eq('area' => '800 m²')
      expect(ana.name).to eq('Ana')
    end
  end

  describe 'scansolo:smoke' do
    subject(:task) { described_class['scansolo:smoke'] }

    let(:account) { create(:account, scansolo_enabled: true) }
    let(:inbox) { create(:inbox, account: account) }

    before do
      task.reenable
      load Rails.root.join('db/seeds/scansolo_cadence_definitions.rb')
      create(:installation_config, name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'sk-secret-openai-key')
      ScanSolo::AiAgentConfig.draft_for!(account).update!(name: 'Agente', enabled: true, allowed_inbox_ids: [inbox.id])
      ScanSolo::AiAgent::PublishService.new(account: account).call
      allow(Sidekiq::Cron::Job).to receive(:find).with('scan_solo_cadence_due_attempt_job').and_return(instance_double(Sidekiq::Cron::Job))
      allow(ScanSolo::Proposal::Integration).to receive(:configured?).and_return(true)
    end

    it 'prints PASS for every check and exits cleanly on a ready deploy' do
      with_modified_env EXPECTED_GIT_SHA: GIT_HASH do
        expect { task.invoke(account.id) }.to output(/PASS git_sha.*PASS proposal_integration.*ScanSolo smoke passed/m).to_stdout
      end
    end

    {
      'git_sha' => -> { ENV['EXPECTED_GIT_SHA'] = 'deadbeef' },
      'pending_migrations' => lambda {
        allow(ActiveRecord::Base.connection_pool).to receive(:migration_context)
          .and_return(instance_double(ActiveRecord::MigrationContext, needs_migration?: true))
      },
      'cadence_definitions' => -> { ScanSolo::CadenceDefinition.find_by!(stage: 'proposta_enviada').update!(active: false) },
      'llm_key_configured' => -> { InstallationConfig.where(name: 'CAPTAIN_OPEN_AI_API_KEY').destroy_all },
      'agent_config' => lambda {
        ScanSolo::AiAgentConfig.draft_for!(account).update!(allowed_inbox_ids: [])
        ScanSolo::AiAgent::PublishService.new(account: account).call
      },
      'inbox_conflicts' => -> { create(:agent_bot_inbox, inbox: inbox, status: :active) },
      'cadence_cron_registered' => -> { allow(Sidekiq::Cron::Job).to receive(:find).and_return(nil) },
      'proposal_integration' => -> { allow(ScanSolo::Proposal::Integration).to receive(:configured?).and_return(false) }
    }.each do |check, break_check|
      it "exits non-zero naming #{check} when it fails" do
        with_modified_env EXPECTED_GIT_SHA: GIT_HASH do
          instance_exec(&break_check)

          expect { task.invoke(account.id) }
            .to raise_error(SystemExit) { |error| expect(error.status).not_to eq(0) }
            .and output(/FAIL #{check}/).to_stdout
            .and output(/ScanSolo smoke failed: #{check}\n/).to_stderr
        end
      end
    end
  end
end
