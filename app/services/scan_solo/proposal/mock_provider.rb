# RF-83: usable without any real proposal API/Make production credential --
# the sole provider ScanSolo::Proposal::GenerateService/SendService talk to
# in this phase (a real Make-backed provider is a separate future injection
# point behind the same two class methods, mirroring
# ScanSolo::AiTurn::ModelInvoker's `llm_provider` seam). Every call here is
# synchronous pure Ruby -- no HTTP client -- so the full T59-T63 proposal
# suite passes with zero outbound request and zero production credential.
#
# `outcome:` lets a caller (a spec, or a future retry) simulate a provider-
# side failure without ever touching a real endpoint; the actual state
# change is always applied through ScanSolo::Proposal::CallbackHandler,
# never here directly (RF-75/RF-76).
class ScanSolo::Proposal::MockProvider
  DEFAULT_VALUE = 1500.0
  DEFAULT_CURRENCY = 'BRL'.freeze

  # rubocop:disable Metrics/ParameterLists
  def self.request_generation(proposal_version:, correlation_id:, outcome: :success, value: DEFAULT_VALUE,
                              currency: DEFAULT_CURRENCY, artifact_url: nil, failure_reason: 'mock_generation_failed')
    # rubocop:enable Metrics/ParameterLists
    ScanSolo::Proposal::CallbackHandler.apply_generate_result!(
      proposal_version: proposal_version,
      correlation_id: correlation_id,
      success: outcome == :success,
      value: value,
      currency: currency,
      artifact_url: artifact_url || "https://mock-proposals.scansolo.test/#{proposal_version.id}.pdf",
      failure_reason: failure_reason
    )
  end

  # rubocop:disable Metrics/ParameterLists
  def self.request_send(proposal_version:, correlation_id:, conversation:, actor: nil, outcome: :success,
                        template_reference: ScanSolo::Proposal::CallbackHandler::DEFAULT_SEND_TEMPLATE,
                        failure_reason: 'mock_send_failed')
    # rubocop:enable Metrics/ParameterLists
    ScanSolo::Proposal::CallbackHandler.apply_send_result!(
      proposal_version: proposal_version,
      correlation_id: correlation_id,
      success: outcome == :success,
      conversation: conversation,
      template_reference: template_reference,
      actor: actor,
      failure_reason: failure_reason
    )
  end
end
