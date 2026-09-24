# RF-38 / RF-39 / CT-06: turns a ScanSolo::Make::CallbackVerifier result
# into persisted state. A rejected callback (`malformed_json`,
# `schema_invalid`, `unmatched_request`) is recorded with `applied: false`
# and never reserves its correlation id, so a later valid callback for the
# same correlation id still applies. A valid callback is applied at most
# once per correlation id: the MakeCallback row (`applied: true`, protected
# by the partial unique index), the MakeRequest status and the
# ProposalVersion update through ScanSolo::Proposal::CallbackHandler happen
# in one transaction.
#
# A Make failure flagged `retryable` is recorded as `provider_unavailable`
# so ScanSolo::Proposal::RetryPolicy accepts it; a non-retryable failure
# keeps Make's own `error_code`.
class ScanSolo::Make::CallbackApplicationService
  def self.call(result:)
    new(result: result).call
  end

  def initialize(result:)
    @result = result
  end

  # Returns :applied, :duplicate or :rejected.
  def call
    return reject! unless result.valid?
    return :duplicate if ScanSolo::MakeCallback.applied.exists?(correlation_id: correlation_id)

    ActiveRecord::Base.transaction do
      ScanSolo::MakeCallback.create!(correlation_id: correlation_id, action: action, signature_valid: true, applied: true, payload: payload)
      make_request.update!(status: success? ? :completed : :failed)
      action == 'proposal.generate' ? apply_generate! : apply_send!
    end
    :applied
  rescue ActiveRecord::RecordNotUnique
    :duplicate
  end

  private

  attr_reader :result

  delegate :payload, :make_request, to: :result

  def reject!
    ScanSolo::MakeCallback.create!(
      correlation_id: payload&.dig('correlation_id'),
      action: payload&.dig('action'),
      signature_valid: result.signature_valid,
      applied: false,
      rejection_reason: result.rejection_reason,
      payload: payload || {}
    )
    :rejected
  end

  def apply_generate!
    version = proposal_version(:generate_correlation_id)
    ScanSolo::Proposal::CallbackHandler.apply_generate_result!(
      proposal_version: version, correlation_id: correlation_id, success: success?,
      value: callback_result['total_value'], currency: callback_result['currency'], artifact_url: callback_result['artifact_url'],
      failure_reason: failure_reason
    )
  end

  def apply_send!
    version = proposal_version(:send_correlation_id)
    ScanSolo::Proposal::CallbackHandler.apply_send_result!(
      proposal_version: version, correlation_id: correlation_id, success: success?,
      conversation: version.proposal.opportunity.conversation,
      actor: make_request.account.users.find_by(id: make_request.payload['requested_by_user_id']),
      failure_reason: failure_reason
    )
  end

  def proposal_version(correlation_column)
    ScanSolo::ProposalVersion.joins(proposal: :opportunity)
                             .where(scan_solo_pipeline_opportunities: { account_id: make_request.account_id })
                             .find_by!(correlation_column => correlation_id)
  end

  def failure_reason
    return if success?

    callback_result['retryable'] ? 'provider_unavailable' : callback_result['error_code']
  end

  def success?
    payload['status'] == 'success'
  end

  def callback_result
    payload['result'] || {}
  end

  def correlation_id
    payload['correlation_id']
  end

  def action
    payload['action']
  end
end
