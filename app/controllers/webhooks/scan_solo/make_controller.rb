# CT-06 / RF-38 / RF-39: the sole unauthenticated-caller-reachable endpoint
# in the whole ScanSolo layer. Trust decisions live entirely in
# ScanSolo::Make::CallbackVerifier and persistence in
# ScanSolo::Make::CallbackApplicationService; this controller only maps
# their outcome to a status: 401 for an invalid signature (nothing
# persisted), 422 for any other rejection, 200 for an applied callback and
# for a redelivery of an already-applied correlation id.
class Webhooks::ScanSolo::MakeController < ActionController::API
  def process_callback
    result = ScanSolo::Make::CallbackVerifier.call(raw_body: request.body.read, signature: request.headers['X-Make-Signature'])
    return head :unauthorized if result.rejection_reason == 'invalid_signature'

    outcome = ScanSolo::Make::CallbackApplicationService.call(result: result)
    head(outcome == :rejected ? :unprocessable_entity : :ok)
  end
end
