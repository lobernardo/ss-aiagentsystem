# RF-02/RF-03: the single rule that derives an opportunity's lead_source from
# the first public incoming/outgoing message of its conversation (activity,
# template and private notes are ignored). A customer's incoming message means
# the lead came from the site/WhatsApp; a native outgoing message sent by a
# team member (User) means the commercial team opened it; anything else
# (campaign, bot, automation, no messages) stays nil ("Não informada").
class ScanSolo::Pipeline::LeadSourceClassifier
  def self.call(conversation:)
    first_message = conversation.messages
                                .where(private: false, message_type: %i[incoming outgoing])
                                .order(:created_at, :id)
                                .first
    return if first_message.blank?
    return 'website' if first_message.incoming?

    'manual' if first_message.sender_type == 'User'
  end
end
