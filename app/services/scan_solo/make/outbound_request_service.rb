# CT-08 / RF-84 / RF-85: the sole path that ever issues an outbound HTTP
# request to the account's registered Make scenario. Reads the scenario
# endpoint and outbound secret exclusively from Rails encrypted credentials
# (config/credentials.yml.enc, server-side only, never a caller-suppliable
# value) and raises loudly on a missing/misconfigured entry rather than
# silently no-op'ing (a missing production credential is a deployment bug,
# not a runtime case to swallow). Attaches a correlation id and idempotency
# key to every outbound request (RF-85). Persists a ScanSolo::MakeRequest
# evidence row -- created before the HTTP call, updated with the outcome
# after -- so a failure is always visible for retry/dead-letter review
# (T70) even when the request itself raises.
#
# Never called from the default AI-turn message-response path: only a
# registered Make-backed action (e.g. proposal.generate/proposal.send)
# invokes this service explicitly (RF-84).
class ScanSolo::Make::OutboundRequestService
  class NotConfiguredError < StandardError; end

  REQUEST_TIMEOUT = 10

  def self.call(account:, action:, payload:, correlation_id: SecureRandom.uuid, idempotency_key: SecureRandom.uuid)
    new(
      account: account, action: action, payload: payload, correlation_id: correlation_id, idempotency_key: idempotency_key
    ).call
  end

  def initialize(account:, action:, payload:, correlation_id:, idempotency_key:)
    @account = account
    @action = action.to_s
    @payload = payload
    @correlation_id = correlation_id
    @idempotency_key = idempotency_key
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
      status: :pending
    )

    deliver!(request)
    request
  end

  private

  attr_reader :account, :action, :payload, :correlation_id, :idempotency_key

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

    request.update!(
      status: response.success? ? :sent : :failed,
      retry_count: response.success? ? request.retry_count : request.retry_count + 1
    )
  rescue StandardError => e
    request.update!(status: :failed, retry_count: request.retry_count + 1)
    Rails.logger.error("[ScanSolo::Make] outbound request errored: #{e.class}")
    raise
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
