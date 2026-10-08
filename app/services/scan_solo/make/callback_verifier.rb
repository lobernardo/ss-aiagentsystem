# CT-09 / RF-85 / RF-86 / RF-87: the sole place that decides whether an
# inbound Make callback may be trusted, in strict order -- signature over
# the raw body first (before any parsing), then JSON parsing, then
# schema validation against the registered CT-09 response contract, then
# a check that the correlation id/action was actually issued by
# ScanSolo::Make::OutboundRequestService (T67) for this exact action. No
# generic/arbitrary callback can mutate state outside this contract
# (RF-87). Returns a Result the controller uses to decide what to persist
# and whether to apply anything -- this service never itself persists or
# mutates state, keeping the trust decision and its side effects separate.
# CT-08 / RF-25: a generate success may carry the optional `artifact_sha256`
# (64 lowercase hex) and `template_version`.
class ScanSolo::Make::CallbackVerifier
  SCHEMA = {
    'type' => 'object',
    'required' => %w[correlation_id idempotency_key action status],
    'properties' => {
      'correlation_id' => { 'type' => 'string', 'minLength' => 1 },
      'idempotency_key' => { 'type' => 'string', 'minLength' => 1 },
      'action' => { 'type' => 'string', 'enum' => %w[proposal.generate proposal.send] },
      'status' => { 'type' => 'string', 'enum' => %w[success failure] },
      'result' => {
        'type' => 'object',
        'oneOf' => [
          {
            'type' => 'object',
            'required' => %w[proposal_version_id artifact_url total_value currency valid_until],
            'properties' => {
              'proposal_version_id' => { 'type' => 'integer' },
              'artifact_url' => { 'type' => 'string' },
              'total_value' => { 'type' => 'number' },
              'currency' => { 'type' => 'string', 'minLength' => 3, 'maxLength' => 3 },
              'valid_until' => { 'type' => 'string' },
              'artifact_sha256' => { 'type' => 'string', 'pattern' => '^[0-9a-f]{64}$' },
              'template_version' => { 'type' => 'string', 'minLength' => 1 }
            }
          },
          {
            'type' => 'object',
            'required' => %w[proposal_version_id sent_at transport_message_id],
            'properties' => {
              'proposal_version_id' => { 'type' => 'integer' },
              'sent_at' => { 'type' => 'string' },
              'transport_message_id' => { 'type' => 'string' }
            }
          },
          {
            'type' => 'object',
            'required' => %w[proposal_version_id error_code error_message retryable],
            'properties' => {
              'proposal_version_id' => { 'type' => 'integer' },
              'error_code' => { 'type' => 'string' },
              'error_message' => { 'type' => 'string' },
              'retryable' => { 'type' => 'boolean' }
            }
          }
        ]
      }
    }
  }.freeze

  Result = Struct.new(:signature_valid, :rejection_reason, :payload, :make_request, keyword_init: true) do
    def valid?
      rejection_reason.nil?
    end
  end

  def self.call(raw_body:, signature:)
    new(raw_body: raw_body, signature: signature).call
  end

  def initialize(raw_body:, signature:)
    @raw_body = raw_body
    @signature = signature
  end

  def call
    return reject(signature_valid: false, reason: 'invalid_signature') unless signature_valid?

    payload = parse_json
    return reject(signature_valid: true, reason: 'malformed_json') if payload.nil?
    return reject(signature_valid: true, reason: 'schema_invalid', payload: payload) if schema_errors(payload).any?

    make_request = ScanSolo::MakeRequest.find_by(correlation_id: payload['correlation_id'], action: payload['action'])
    return reject(signature_valid: true, reason: 'unmatched_request', payload: payload) if make_request.blank?

    Result.new(signature_valid: true, rejection_reason: nil, payload: payload, make_request: make_request)
  end

  private

  attr_reader :raw_body, :signature

  def signature_valid?
    secret = Rails.application.credentials.dig(:scan_solo, :make, :inbound_signing_secret)
    return false if secret.blank? || signature.blank?

    computed = OpenSSL::HMAC.hexdigest('SHA256', secret, raw_body.to_s)
    ActiveSupport::SecurityUtils.secure_compare(computed, signature)
  end

  def parse_json
    JSON.parse(raw_body.to_s)
  rescue JSON::ParserError, TypeError
    nil
  end

  def schema_errors(payload)
    JSONSchemer.schema(SCHEMA).validate(payload).to_a
  end

  def reject(signature_valid:, reason:, payload: nil)
    Result.new(signature_valid: signature_valid, rejection_reason: reason, payload: payload, make_request: nil)
  end
end
