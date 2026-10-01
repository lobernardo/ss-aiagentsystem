# RF-19/RF-23: an incoming email on the quote inbox that is not (or no longer)
# readable as a quote reply waits here for a manual decision (CT-08). The
# unique index on message_id keeps one entry per email.
# == Schema Information
#
# Table name: scan_solo_quote_replies
#
#  id               :bigint           not null, primary key
#  kind             :integer
#  resolved_at      :datetime
#  status           :integer          default("pending"), not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  account_id       :bigint           not null
#  conversation_id  :bigint
#  message_id       :bigint           not null
#  quote_request_id :bigint
#  resolved_by_id   :bigint
#
# Indexes
#
#  index_scan_solo_quote_replies_on_account_id_and_status  (account_id,status)
#  index_scan_solo_quote_replies_on_message_id             (message_id) UNIQUE
#  index_scan_solo_quote_replies_on_quote_request_id       (quote_request_id)
#  index_scan_solo_quote_replies_on_resolved_by_id         (resolved_by_id)
#
# Foreign Keys
#
#  fk_rails_...  (quote_request_id => scan_solo_quote_requests.id)
#  fk_rails_...  (resolved_by_id => users.id)
#
class ScanSolo::QuoteReply < ApplicationRecord
  self.table_name = 'scan_solo_quote_replies'

  belongs_to :account
  belongs_to :message
  belongs_to :quote_request, class_name: 'ScanSolo::QuoteRequest', optional: true
  belongs_to :resolved_by, class_name: 'User', optional: true

  enum kind: { unmatched: 0, late_reply: 1 }
  enum status: { pending: 0, linked: 1, discarded: 2 }
end
