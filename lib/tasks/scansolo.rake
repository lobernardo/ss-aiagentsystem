namespace :scansolo do
  desc 'Load the ScanSolo cadence definitions (idempotent, RF-25) and print the active ones'
  task load_cadence_definitions: :environment do
    load Rails.root.join('db/seeds/scansolo_cadence_definitions.rb')

    ScanSolo::CadenceDefinition.active.order(:stage, :version).each do |definition|
      puts "#{definition.stage} v#{definition.version}: #{definition.offsets.inspect}"
    end
  end

  desc 'Smoke-check a ScanSolo deploy (RF-58): prints PASS/FAIL per check and exits non-zero on any failure'
  task :smoke, [:account_id] => :environment do |_task, args|
    report = ScanSolo::StatusReport.call(account: Account.find(args.fetch(:account_id)))

    report.checks.each { |name, passed| puts "#{passed ? 'PASS' : 'FAIL'} #{name}" }
    abort("ScanSolo smoke failed: #{report.failed_checks.join(', ')}") if report.failed_checks.any?

    puts 'ScanSolo smoke passed'
  end
end
