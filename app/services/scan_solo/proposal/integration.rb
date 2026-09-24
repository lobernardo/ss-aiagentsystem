class ScanSolo::Proposal::Integration
  REQUIRED_CREDENTIALS = %i[scenario_url secret inbound_signing_secret].freeze

  def self.configured?
    REQUIRED_CREDENTIALS.all? { |key| Rails.application.credentials.dig(:scan_solo, :make, key).present? }
  end

  def self.state
    configured? ? 'configured' : 'blocked'
  end

  def self.provider!
    return ScanSolo::Proposal::MakeProvider if configured?
    return ScanSolo::Proposal::MockProvider if !Rails.env.production? && (Rails.env.test? || Rails.env.development?)

    raise CustomExceptions::ScanSolo::ProposalIntegrationNotConfigured
  end
end
