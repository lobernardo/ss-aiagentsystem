# rubocop:disable Metrics/BlockLength
namespace :scansolo do
  desc 'Load the ScanSolo cadence definitions (idempotent, RF-25) and print the active ones'
  task load_cadence_definitions: :environment do
    load Rails.root.join('db/seeds/scansolo_cadence_definitions.rb')

    ScanSolo::CadenceDefinition.active.order(:stage, :version).each do |definition|
      puts "#{definition.stage} v#{definition.version}: #{definition.offsets.inspect}"
    end
  end

  desc 'Create the lead state of every ScanSolo opportunity that has none (RF-01a); additive, never writes to contacts'
  task backfill_lead_states: :environment do
    backfilled_at = Time.current
    created = 0

    ScanSolo::PipelineOpportunity.where.missing(:lead_state).find_each do |opportunity|
      ScanSolo::LeadState::InitializeService.call(opportunity: opportunity, backfilled_at: backfilled_at)
      created += 1
    end

    puts "Lead states created: #{created}"
  end

  desc 'Fill the lead_source of ScanSolo opportunities that have none (RF-03); idempotent, skips callbacks and updated_at'
  task backfill_lead_source: :environment do
    updated = 0

    ScanSolo::PipelineOpportunity.where(lead_source: nil).includes(:conversation).find_each do |opportunity|
      lead_source = ScanSolo::Pipeline::LeadSourceClassifier.call(conversation: opportunity.conversation)
      next if lead_source.nil?

      opportunity.update_columns(lead_source: lead_source) # rubocop:disable Rails/SkipsModelValidations
      updated += 1
    end

    puts "Lead sources backfilled: #{updated}"
  end

  desc 'Smoke-check a ScanSolo deploy (RF-58): prints PASS/FAIL per check and exits non-zero on any failure'
  task :smoke, [:account_id] => :environment do |_task, args|
    report = ScanSolo::StatusReport.call(account: Account.find(args.fetch(:account_id)))

    report.checks.each { |name, passed| puts "#{passed ? 'PASS' : 'FAIL'} #{name}" }
    abort("ScanSolo smoke failed: #{report.failed_checks.join(', ')}") if report.failed_checks.any?

    puts 'ScanSolo smoke passed'
  end
end
# rubocop:enable Metrics/BlockLength
