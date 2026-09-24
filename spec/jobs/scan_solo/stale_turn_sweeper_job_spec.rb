# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::StaleTurnSweeperJob do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

  def incoming
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, sender: contact)
  end

  def turn_for(message, status: :pending, created_at: Time.current)
    ScanSolo::AiTurn.create!(message: message, conversation: conversation, correlation_id: SecureRandom.uuid,
                             invocation_status: status, created_at: created_at)
  end

  it 'fails a pending turn created 11 minutes ago with stale_pending' do
    turn = turn_for(incoming, created_at: 11.minutes.ago)

    described_class.perform_now

    expect(turn.reload).to have_attributes(invocation_status: 'failed', failure_reason: 'stale_pending')
  end

  it 'leaves recent pending turns and terminal turns untouched' do
    recent = turn_for(incoming, created_at: 9.minutes.ago)
    old_succeeded = turn_for(incoming, status: :succeeded, created_at: 1.hour.ago)

    expect { described_class.perform_now }.not_to(change { [recent.reload.attributes, old_succeeded.reload.attributes] })
  end

  it 'sends nothing when the message job runs after the sweep (RF-08)' do
    draft = ScanSolo::AiAgentConfig.draft_for!(account)
    draft.update!(name: 'Agente ScanSolo', enabled: true, allowed_inbox_ids: [inbox.id])
    ScanSolo::AiAgent::PublishService.new(account: account).call
    message = incoming
    turn_for(message, created_at: 11.minutes.ago)

    described_class.perform_now
    ScanSolo::AiTurnJob.perform_now(message.id, llm_provider: 'ScanSolo::TestMode::MockLlmProvider')

    expect(conversation.messages.outgoing.count).to eq(0)
    expect(ScanSolo::AiTurn.find_by!(message_id: message.id).failure_reason).to eq('stale_pending')
  end

  it 'is registered in config/schedule.yml every 5 minutes on the scheduled_jobs queue' do
    entry = YAML.load_file(Rails.root.join('config/schedule.yml')).fetch('scan_solo_stale_turn_sweeper_job')

    expect(entry).to eq('cron' => '*/5 * * * *', 'class' => 'ScanSolo::StaleTurnSweeperJob', 'queue' => 'scheduled_jobs')
  end

  it 'uses the 10 minute stale threshold (RNF-02)' do
    expect(ScanSolo::AI_TURN_STALE_THRESHOLD).to eq(10.minutes)
  end
end
