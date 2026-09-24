# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::StatusReport do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:last_sync) { Time.zone.parse('2026-09-20 12:00:00') }
  let(:channel) do
    create(:channel_whatsapp, account: account, sync_templates: false, message_templates_last_updated: last_sync)
  end
  let(:web_inbox) { create(:inbox, account: account) }
  let(:report) { described_class.call(account: account, expected_git_sha: GIT_HASH) }

  before do
    stub_request(:post, 'https://waba.360dialog.io/v1/configs/webhook')
    load Rails.root.join('db/seeds/scansolo_cadence_definitions.rb')
    create(:installation_config, name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'sk-secret-openai-key')
    ScanSolo::AiAgentConfig.draft_for!(account).update!(name: 'Agente', enabled: true, model_selection: 'gpt-4.1-mini',
                                                        allowed_inbox_ids: [channel.inbox.id, web_inbox.id])
    ScanSolo::AiAgent::PublishService.new(account: account).call
    allow(Sidekiq::Cron::Job).to receive(:find).with('scan_solo_cadence_due_attempt_job').and_return(instance_double(Sidekiq::Cron::Job))
    allow(ScanSolo::Proposal::Integration).to receive(:configured?).and_return(true)
  end

  it 'summarizes every RF-58 check with passing values for a ready account' do
    expect(report).to have_attributes(
      git_sha: GIT_HASH, pending_migrations: false, llm_key_configured: true, inbox_conflicts: [],
      cadence_cron_registered: true, proposal_integration: 'configured'
    )
    expect(report.cadence_definitions).to eq('novo_lead' => 1, 'em_contato' => 1, 'em_qualificacao' => 1, 'proposta_enviada' => 1)
    expect(report.agent).to eq(published: true, enabled: true, model: 'gpt-4.1-mini', allowed_inbox_ids: [channel.inbox.id, web_inbox.id])
    expect(report.templates_last_synced_at).to eq(channel.inbox.id.to_s => last_sync)
    expect(report.failed_checks).to be_empty
  end

  it 'reports a missing cadence definition, an allowlisted inbox with an active bot and a blocked integration' do
    ScanSolo::CadenceDefinition.find_by!(stage: 'em_contato').update!(active: false)
    create(:agent_bot_inbox, inbox: web_inbox, status: :active)
    allow(ScanSolo::Proposal::Integration).to receive(:configured?).and_return(false)

    expect(report.cadence_definitions['em_contato']).to be_nil
    expect(report.inbox_conflicts).to eq([web_inbox.id])
    expect(report.proposal_integration).to eq('blocked')
    expect(report.failed_checks).to contain_exactly('cadence_definitions', 'inbox_conflicts', 'proposal_integration')
  end

  it 'fails the git_sha check when the expected sha is absent or differs' do
    expect(described_class.call(account: account, expected_git_sha: nil).failed_checks).to eq(['git_sha'])
    expect(described_class.call(account: account, expected_git_sha: 'deadbeef').failed_checks).to eq(['git_sha'])
  end
end
