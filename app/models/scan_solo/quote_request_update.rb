# RF-14 (c): one update e-mail per quote request and qualification version.
# The unique index on (quote_request_id, version_digest) is the database
# guarantee; the validation turns the common case into a readable error.
# == Schema Information
#
# Table name: scan_solo_quote_request_updates
#
#  id               :bigint           not null, primary key
#  sent_at          :datetime
#  version_digest   :string           not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  account_id       :bigint           not null
#  message_id       :bigint
#  quote_request_id :bigint           not null
#
# Indexes
#
#  index_scan_solo_quote_request_updates_on_account_id          (account_id)
#  index_scan_solo_quote_request_updates_on_request_and_digest  (quote_request_id,version_digest) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (quote_request_id => scan_solo_quote_requests.id)
#
class ScanSolo::QuoteRequestUpdate < ApplicationRecord
  self.table_name = 'scan_solo_quote_request_updates'

  belongs_to :quote_request, class_name: 'ScanSolo::QuoteRequest', inverse_of: :updates
  belongs_to :account
  belongs_to :message, optional: true

  validates :version_digest, presence: true, uniqueness: { scope: :quote_request_id }
end
