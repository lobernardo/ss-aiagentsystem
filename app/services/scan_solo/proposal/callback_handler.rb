# RF-75/RF-76/RF-79/RF-80: the sole writer of ProposalVersion#value/
# currency/artifact_url (generate) and the sole path that creates the native
# proposal message (send) -- reachable only from a validated provider
# result, never from GenerateService/SendService directly (RF-76: the
# model's raw output never reaches these fields through any other path).
# Idempotent: delivering the same callback twice applies the state change
# exactly once, guarded by generate_callback_applied_at/
# send_callback_applied_at read under a row lock (RF-80).
#
# A successful send result resolves the proposal template (RF-32) and checks
# its availability (RF-33) before creating the native message; the version
# only becomes `sent` -- and the stage `proposta_enviada` -- once
# ScanSolo::Messaging::DeliveryReconciler sees the provider accept that
# message (RF-41).
class ScanSolo::Proposal::CallbackHandler
  # rubocop:disable Metrics/ParameterLists
  def self.apply_generate_result!(proposal_version:, correlation_id:, success:, value: nil, currency: nil,
                                  artifact_url: nil, failure_reason: nil)
    # rubocop:enable Metrics/ParameterLists
    proposal_version.with_lock do
      # RF-87-style guard: only a callback matching the correlation id this
      # version's generate request was actually issued under may apply a
      # result, even for the mock provider.
      next unless correlation_id == proposal_version.generate_correlation_id
      next if proposal_version.generate_callback_applied_at.present?

      if success
        proposal_version.update!(
          status: :generated, value: value, currency: currency, artifact_url: artifact_url,
          generate_callback_applied_at: Time.current
        )
      else
        proposal_version.update!(status: :failed, failure_reason: failure_reason, generate_callback_applied_at: Time.current)
      end
    end

    proposal_version
  end

  # rubocop:disable Metrics/ParameterLists
  def self.apply_send_result!(proposal_version:, correlation_id:, success:, conversation: nil, actor: nil, failure_reason: nil)
    # rubocop:enable Metrics/ParameterLists
    proposal_version.with_lock do
      next unless correlation_id == proposal_version.send_correlation_id
      next if proposal_version.send_callback_applied_at.present?

      if success
        apply_successful_send!(proposal_version, conversation: conversation, actor: actor)
      else
        proposal_version.update!(status: :failed, failure_reason: failure_reason, send_callback_applied_at: Time.current)
      end
    end

    proposal_version
  end

  def self.apply_successful_send!(proposal_version, conversation:, actor:)
    opportunity = proposal_version.proposal.opportunity
    template = ScanSolo::Messaging::TemplateResolver.call(account: opportunity.account, stage: 'proposta_enviada', step: nil,
                                                          opportunity: opportunity)
    guard = ScanSolo::Cadence::TemplateAvailabilityGuard.check(inbox: conversation.inbox, template: template)
    if guard.blocked?
      proposal_version.update!(status: :failed, failure_reason: guard.reason, send_callback_applied_at: Time.current)
      return
    end

    message = ScanSolo::Messaging::NativeTemplateSender.call(
      conversation: conversation, template_reference: template.name, origin: 'proposal', actor: actor,
      template_params: template.sender_params.merge(fallback_content: proposal_version.artifact_url)
    ).message

    proposal_version.update!(sent_message: message, send_callback_applied_at: Time.current)
  end
  private_class_method :apply_successful_send!
end
