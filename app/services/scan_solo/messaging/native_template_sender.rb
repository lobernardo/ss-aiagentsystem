# RF-34: the sole path cadence and proposal-send steps use to deliver a
# WhatsApp template message -- always through the native
# `conversation.messages.create!` path with `template_params` (name,
# language and the native `processed_params` resolved by
# ScanSolo::Messaging::TemplateResolver), which native
# Whatsapp::SendOnWhatsappService delivers. Never a parallel HTTP client to
# Meta, never a third-party WhatsApp gateway. A fake/test template reference works exactly the
# same way: native message creation doesn't require the template to be
# pre-approved, only ScanSolo::Cadence::TemplateAvailabilityGuard enforces
# that for real WhatsApp channels before this class is ever called.
#
# This class only creates the native message; it never asserts "sent" on
# the caller's behalf. Native Chatwoot's own transport (the `SendReplyJob`
# enqueued automatically by Message#send_reply on create) is the only thing
# that accepts or rejects the send, flipping `message.status` to `failed`
# on rejection -- so a caller must read the returned message's own status
# to know the outcome, and never invents a separate "sent" flag here
# (RF-72).
#
# `origin` (`cadence` or `proposal`) is stored as `scansolo_origin` so the
# listener never mistakes a ScanSolo send -- even one carrying an actor user,
# like the proposal send -- for a manual human reply (RF-18).
class ScanSolo::Messaging::NativeTemplateSender
  Result = Struct.new(:message, keyword_init: true)

  def self.call(conversation:, template_reference:, origin:, template_params: {}, actor: nil)
    new(conversation: conversation, template_reference: template_reference, origin: origin, template_params: template_params,
        actor: actor).call
  end

  def initialize(conversation:, template_reference:, origin:, template_params: {}, actor: nil)
    @conversation = conversation
    @template_reference = template_reference
    @origin = origin
    @template_params = template_params
    @actor = actor
  end

  def call
    message = conversation.messages.create!(
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      message_type: :outgoing,
      content: template_params[:fallback_content].presence || template_reference,
      sender: actor,
      additional_attributes: { 'template_params' => native_template_params, 'scansolo_origin' => origin }
    )

    Result.new(message: message)
  end

  private

  attr_reader :conversation, :template_reference, :origin, :template_params, :actor

  def native_template_params
    {
      'name' => template_reference,
      'category' => template_params[:category],
      'language' => template_params[:language] || 'pt_BR',
      'namespace' => template_params[:namespace],
      'processed_params' => template_params[:processed_params] || {}
    }.compact
  end
end
