# RF-17 / RNF-03: reads an incoming e-mail of the published quote inbox,
# enqueued by ScanSolo::ConversationListener on the native message creation
# (no cron, 0 extra polling cycles).
class ScanSolo::QuoteReplyJob < ApplicationJob
  queue_as :medium

  def perform(message_id)
    ScanSolo::Quote::ReplyProcessor.call(message: Message.find(message_id))
  end
end
