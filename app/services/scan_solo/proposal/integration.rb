# RF-01, RF-19, CT-08, CT-09: `SCANSOLO_GOTENBERG_URL` turns the local mode on,
# which takes precedence over the Make credentials. In local mode the
# integration state is per account: `configured` only with an active template.
class ScanSolo::Proposal::Integration
  REQUIRED_CREDENTIALS = %i[scenario_url secret inbound_signing_secret].freeze

  def self.local?
    ENV['SCANSOLO_GOTENBERG_URL'].present?
  end

  def self.configured?
    REQUIRED_CREDENTIALS.all? { |key| Rails.application.credentials.dig(:scan_solo, :make, key).present? }
  end

  def self.state(account)
    ready = local? ? ScanSolo::ProposalTemplate.active_for(account).present? : configured?
    ready ? 'configured' : 'blocked'
  end

  def self.provider!
    return ScanSolo::Proposal::LocalProvider if local?
    return ScanSolo::Proposal::MakeProvider if configured?
    return ScanSolo::Proposal::MockProvider if !Rails.env.production? && (Rails.env.test? || Rails.env.development?)

    raise CustomExceptions::ScanSolo::ProposalIntegrationNotConfigured
  end
end
