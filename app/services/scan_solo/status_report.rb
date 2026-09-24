# RF-58/RF-60/RNF-04: the operational checks shared by the administrator
# status endpoint (CT-07) and `bundle exec rails scansolo:smoke[account_id]`.
# Credentials are only ever reported as presence booleans -- no key, secret
# or URL value leaves this object.
class ScanSolo::StatusReport
  CADENCE_STAGES = ScanSolo::TemplateMapping::STAGES
  CADENCE_CRON_JOB = 'scan_solo_cadence_due_attempt_job'.freeze

  def self.call(account:, expected_git_sha: ENV.fetch('EXPECTED_GIT_SHA', nil))
    new(account: account, expected_git_sha: expected_git_sha)
  end

  def initialize(account:, expected_git_sha:)
    @account = account
    @expected_git_sha = expected_git_sha
  end

  def git_sha
    GIT_HASH
  end

  def pending_migrations
    @pending_migrations = ActiveRecord::Base.connection_pool.migration_context.needs_migration? if @pending_migrations.nil?
    @pending_migrations
  end

  def cadence_definitions
    @cadence_definitions ||= CADENCE_STAGES.index_with { |stage| ScanSolo::CadenceDefinition.current_for(stage)&.version }
  end

  def llm_key_configured
    InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY')&.value.present?
  end

  def agent
    {
      published: config.present?,
      enabled: config&.enabled || false,
      model: config&.model_selection,
      allowed_inbox_ids: allowed_inbox_ids
    }
  end

  def inbox_conflicts
    allowlisted_inboxes.select(&:active_bot?).map(&:id)
  end

  def cadence_cron_registered
    Sidekiq::Cron::Job.find(CADENCE_CRON_JOB).present?
  end

  def proposal_integration
    ScanSolo::Proposal::Integration.state
  end

  def templates_last_synced_at
    allowlisted_inboxes.select { |inbox| inbox.channel.is_a?(Channel::Whatsapp) }
                       .to_h { |inbox| [inbox.id.to_s, inbox.channel.message_templates_last_updated] }
  end

  # RF-58 smoke: every check with its pass/fail outcome, in report order.
  def checks
    @checks ||= {
      'git_sha' => expected_git_sha.present? && git_sha == expected_git_sha,
      'pending_migrations' => !pending_migrations,
      'cadence_definitions' => cadence_definitions.values.all?,
      'llm_key_configured' => llm_key_configured,
      'agent_config' => agent[:published] && agent[:enabled] && allowed_inbox_ids.any?,
      'inbox_conflicts' => inbox_conflicts.empty?,
      'cadence_cron_registered' => cadence_cron_registered,
      'proposal_integration' => proposal_integration == 'configured'
    }
  end

  def failed_checks
    checks.reject { |_name, passed| passed }.keys
  end

  private

  attr_reader :account, :expected_git_sha

  def config
    @config ||= ScanSolo::AiAgentConfig.published_for(account)
  end

  def allowed_inbox_ids
    config&.allowed_inbox_ids.to_a
  end

  def allowlisted_inboxes
    @allowlisted_inboxes ||= account.inboxes.where(id: allowed_inbox_ids).includes(:channel).order(:id).to_a
  end
end
