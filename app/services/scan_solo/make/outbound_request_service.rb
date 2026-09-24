# CT-05 / RF-37: the sole path that ever issues an outbound HTTP request to
# the account's registered Make scenario. Reads the scenario endpoint and
# outbound secret exclusively from Rails encrypted credentials
# (config/credentials.yml.enc, server-side only, never a caller-suppliable
# value) and raises loudly on a missing/misconfigured entry rather than
# silently no-op'ing (a missing production credential is a deployment bug,
# not a runtime case to swallow). Attaches a correlation id and idempotency
# key to every outbound request. Persists a ScanSolo::MakeRequest evidence
# row before the HTTP call and updates it with the outcome after, so a
# failure is always visible for retry/dead-letter review.
#
# Transport failures are classified into the retryable reasons of
# ScanSolo::Proposal::RetryPolicy and raised as DeliveryError, so the caller
# records them on the ProposalVersion instead of letting a raw network
# exception escape.
#
# Never called from the default AI-turn message-response path: only a
# registered Make-backed action (proposal.generate/proposal.send) invokes
# this service explicitly.
class ScanSolo::Make::OutboundRequestService
  class NotConfiguredError < StandardError; end

  class DeliveryError < StandardError
    attr_reader :reason, :make_request

    def initialize(reason:, make_request:)
      @reason = reason
      @make_request = make_request
      super(reason)
    end
  end

  REQUEST_TIMEOUT = 10
  TIMEOUT_ERRORS = [Net::OpenTimeout, Net::ReadTimeout, Timeout::Error].freeze
  NETWORK_ERRORS = [
    SocketError, EOFError, IOError, OpenSSL::SSL::SSLError,
    Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, Errno::ENETUNREACH, Errno::ETIMEDOUT
  ].freeze

  # rubocop:disable Metrics/ParameterLists
  def self.call(account:, action:, payload:, correlation_id: SecureRandom.uuid, idempotency_key: SecureRandom.uuid, retry_count: 0)
    # rubocop:enable Metrics/ParameterLists
    new(
      account: account, action: action, payload: payload, correlation_id: correlation_id, idempotency_key: idempotency_key,
      retry_count: retry_count
    ).call
  end

  # rubocop:disable Metrics/ParameterLists
  def initialize(account:, action:, payload:, correlation_id:, idempotency_key:, retry_count:)
    # rubocop:enable Metrics/ParameterLists
    @account = account
    @action = action.to_s
    @payload = payload
    @correlation_id = correlation_id
    @idempotency_key = idempotency_key
    @retry_count = retry_count
  end

  def call
    scenario_url!
    scenario_secret!

    request = ScanSolo::MakeRequest.create!(
      account: account,
      correlation_id: correlation_id,
      idempotency_key: idempotency_key,
      action: action,
      payload: payload,
      retry_count: retry_count,
      status: :pending
    )

    deliver!(request)
    request
  end

  private

  attr_reader :account, :action, :payload, :correlation_id, :idempotency_key, :retry_count

  def deliver!(request)
    response = HTTParty.post(
      scenario_url!,
      headers: {
        'Content-Type' => 'application/json',
        'Authorization' => "Bearer #{scenario_secret!}",
        'X-Idempotency-Key' => idempotency_key
      },
      body: payload.merge(correlation_id: correlation_id, idempotency_key: idempotency_key, action: action).to_json,
      timeout: REQUEST_TIMEOUT
    )
    return request.update!(status: :sent) if response.success?

    fail_delivery!(request, response.code >= 500 ? 'provider_unavailable' : 'provider_rejected')
  rescue *TIMEOUT_ERRORS => e
    fail_delivery!(request, 'timeout', e)
  rescue *NETWORK_ERRORS => e
    fail_delivery!(request, 'network_error', e)
  end

  def fail_delivery!(request, reason, error = nil)
    request.update!(status: :failed)
    Rails.logger.error("[ScanSolo::Make] outbound request #{correlation_id} failed: #{reason} #{error&.class}")
    raise DeliveryError.new(reason: reason, make_request: request)
  end

  def scenario_url!
    Rails.application.credentials.dig(:scan_solo, :make, :scenario_url).presence or
      raise NotConfiguredError, 'scan_solo.make.scenario_url is not configured'
  end

  def scenario_secret!
    Rails.application.credentials.dig(:scan_solo, :make, :secret).presence or
      raise NotConfiguredError, 'scan_solo.make.secret is not configured'
  end
end
