# CT-05: request human handoff/takeover (RF-51, RF-52), return control to
# AI (RF-52, RF-54), and read the current control state (RF-50, UI-06).
# Both takeover and return_to_ai are idempotent per conversation (RF-53) --
# the idempotency itself lives in the underlying services; this controller
# only adds the authorization gate (RF-54's symmetric assigned-agent-or-
# administrator check).
class Api::V1::Accounts::ScanSolo::Conversations::HandoffController < Api::V1::Accounts::ScanSolo::BaseController
  before_action :set_conversation

  def show
    @extension = ::ScanSolo::ConversationExtension.resolve_for(@conversation)
  end

  def create
    authorize(@conversation, :takeover?, policy_class: ::ScanSolo::HandoffPolicy)

    @extension = ::ScanSolo::Handoff::TakeoverService.call(
      conversation: @conversation, reason: handoff_params[:reason], actor: Current.user
    )

    render :show
  end

  def return_to_ai
    authorize(@conversation, :return_to_ai?, policy_class: ::ScanSolo::HandoffPolicy)

    @extension = ::ScanSolo::Handoff::ReturnToAiService.call(conversation: @conversation, actor: Current.user)

    render :show
  end

  private

  def set_conversation
    @conversation = Conversation.where(account_id: Current.account.id).find(params[:conversation_id])
  end

  def handoff_params
    params.permit(:reason)
  end
end
