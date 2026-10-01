# RF-12/RF-15/RF-22: one quote request per opportunity (unique index on
# opportunity_id), sent to the commercial recipient through the native email
# inbox. The correlation id ties request, reply, generation and audits together.
# == Schema Information
#
# Table name: scan_solo_quote_requests
#
#  id                         :bigint           not null, primary key
#  commercial                 :jsonb            not null
#  replied_at                 :datetime
#  sent_at                    :datetime
#  status                     :integer          default("awaiting_reply"), not null
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  account_id                 :bigint           not null
#  correlation_id             :string           not null
#  customer_notice_message_id :bigint
#  email_conversation_id      :bigint
#  opportunity_id             :bigint           not null
#  reply_message_id           :bigint
#  request_message_id         :bigint
#
# Indexes
#
#  index_scan_solo_quote_requests_on_account_id             (account_id)
#  index_scan_solo_quote_requests_on_correlation_id         (correlation_id) UNIQUE
#  index_scan_solo_quote_requests_on_email_conversation_id  (email_conversation_id) UNIQUE
#  index_scan_solo_quote_requests_on_opportunity_id         (opportunity_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (opportunity_id => scan_solo_pipeline_opportunities.id)
#
class ScanSolo::QuoteRequest < ApplicationRecord
  self.table_name = 'scan_solo_quote_requests'

  belongs_to :opportunity, class_name: 'ScanSolo::PipelineOpportunity', inverse_of: :quote_request
  belongs_to :account
  belongs_to :email_conversation, class_name: 'Conversation', optional: true
  belongs_to :reply_message, class_name: 'Message', optional: true

  has_one :proposal_version,
          class_name: 'ScanSolo::ProposalVersion',
          inverse_of: :quote_request,
          dependent: :restrict_with_exception

  enum status: { awaiting_reply: 0, correction_requested: 1, replied: 2 }

  validates :correlation_id, presence: true

  def open?
    awaiting_reply? || correction_requested?
  end
end
