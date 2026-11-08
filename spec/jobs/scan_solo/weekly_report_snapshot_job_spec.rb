# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::WeeklyReportSnapshotJob do
  # Monday 2026-11-09 06:00 in São Paulo (CT-06): freezes the week of 2026-11-02.
  let(:run_at) { Time.utc(2026, 11, 9, 9, 0, 0) }
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:fixture_content) { 'Meu WhatsApp é +5511988887777 e o e-mail lead.sigiloso@empresa.com.br' }

  it 'is enqueued on the scheduled_jobs queue' do
    expect(described_class.new.queue_name).to eq('scheduled_jobs')
  end

  it 'stores the previous complete week in America/Sao_Paulo (RF-13)' do
    account
    travel_to(run_at) { described_class.perform_now }

    snapshot = ScanSolo::ReportSnapshot.find_by!(account: account)
    expect(snapshot.week_start).to eq(Date.new(2026, 11, 2))
    expect(snapshot.generated_at).to eq(run_at)
    expect(snapshot.payload).to include('period' => 'week', 'anchor' => '2026-11-02', 'source' => 'snapshot',
                                        'starts_at' => '2026-11-02T00:00:00-03:00', 'ends_at' => '2026-11-09T00:00:00-03:00')
  end

  it 'keeps exactly 1 row per week with the payload and generated_at of the 2nd run' do
    account
    travel_to(run_at) { described_class.perform_now }
    second_run_at = run_at + 2.hours
    travel_to(second_run_at) { described_class.perform_now }

    snapshots = ScanSolo::ReportSnapshot.where(account: account)
    expect(snapshots.count).to eq(1)
    expect(snapshots.first.week_start).to eq(Date.new(2026, 11, 2))
    expect(snapshots.first.generated_at).to eq(second_run_at)
    expect(snapshots.first.updated_at).to eq(second_run_at)
    expect(snapshots.first.payload['generated_at']).to eq('2026-11-09T08:00:00-03:00')
  end

  it 'skips accounts without ScanSolo enabled' do
    disabled_account = create(:account, scansolo_enabled: false)
    account

    travel_to(run_at) { described_class.perform_now }

    expect(ScanSolo::ReportSnapshot.where(account: disabled_account)).to be_empty
    expect(ScanSolo::ReportSnapshot.where(account: account).count).to eq(1)
  end

  it 'never stores e-mail, phone or message content (RNF-01)' do
    contact = create(:contact, account: account, name: 'Lead Sigiloso', email: 'lead.sigiloso@empresa.com.br',
                               phone_number: '+5511988887777')
    conversation = create(:conversation, account: account, contact: contact)
    create(:message, account: account, conversation: conversation, message_type: :incoming, content: fixture_content)
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :em_contato,
                                          last_customer_interaction_at: run_at - 3.days, created_at: run_at - 10.days)

    travel_to(run_at) { described_class.perform_now }

    payload = ScanSolo::ReportSnapshot.find_by!(account: account).payload
    expect(payload['stalled'].size).to eq(1)
    serialized = payload.to_json
    expect(serialized).not_to include('@')
    expect(serialized).not_to include('+55')
    expect(serialized).not_to include(fixture_content)
  end

  it 'is scheduled in config/schedule.yml for Monday 06:00 São Paulo (CT-06)' do
    entry = YAML.load_file(Rails.root.join('config/schedule.yml')).fetch('scan_solo_weekly_report_snapshot_job')

    expect(entry).to eq('cron' => '0 9 * * 1', 'class' => 'ScanSolo::WeeklyReportSnapshotJob', 'queue' => 'scheduled_jobs')
  end
end
