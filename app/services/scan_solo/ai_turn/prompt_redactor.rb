# RF-88 / RNF-07: the sole place that decides whether a secret-shaped value
# (an API key/token pattern) may reach a rendered log line or a prompt
# payload sent to the LLM provider. Applied by config/initializers/
# scansolo_log_redaction.rb to every log line and by
# ScanSolo::AiTurn::TurnOrchestrator to the assembled prompt before it is
# handed to ScanSolo::AiTurn::ModelInvoker, so a secret accidentally present
# in stored config/context (e.g. copy-pasted into an agent's instructions)
# never leaves the server boundary.
class ScanSolo::AiTurn::PromptRedactor
  REDACTED = '[REDACTED]'.freeze

  UUID_PATTERN = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

  SECRET_PATTERN = %r{
    (?:sk|pk|rk|ak)[-_](?:live|test)[-_][A-Za-z0-9]{8,}  # vendor-style live-or-test keys (e.g. Stripe)
    | (?:sk|pk|rk|api)[-_][A-Za-z0-9]{16,}                # generic prefixed API keys
    | Bearer\s+[A-Za-z0-9._\-]{10,}                       # bearer tokens
    | \b[A-Za-z0-9_\-]{32,}\b                             # long opaque tokens/secrets
  }xi

  def self.call(value)
    new.call(value)
  end

  def call(value)
    case value
    when String
      value.gsub(SECRET_PATTERN) { |token| UUID_PATTERN.match?(token) ? token : REDACTED }
    when Hash
      value.transform_values { |v| call(v) }
    when Array
      value.map { |v| call(v) }
    else
      value
    end
  end
end
