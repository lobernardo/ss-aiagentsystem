# RF-37/RF-40: one row per outbound Make integration request (CT-05),
# written only by ScanSolo::Make::OutboundRequestService. `retry_count` is the
# number of retries of the proposal operation this request belongs to
# (carried forward by ScanSolo::Proposal::RetryPolicy); the `dead_letter`
# scope surfaces failed requests that reached the retry threshold for the
# Execuções dead-letter view.
# == Schema Information
#
# Table name: scan_solo_make_requests
#
#  id              :bigint           not null, primary key
#  action          :string           not null
#  idempotency_key :string           not null
#  payload         :jsonb            not null
#  retry_count     :integer          default(0), not null
#  status          :integer          default("pending"), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  correlation_id  :string           not null
#
# Indexes
#
#  index_scan_solo_make_requests_on_account_id      (account_id)
#  index_scan_solo_make_requests_on_correlation_id  (correlation_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class ScanSolo::MakeRequest < ApplicationRecord
  self.table_name = 'scan_solo_make_requests'

  DEAD_LETTER_RETRY_THRESHOLD = 3

  belongs_to :account

  enum status: { pending: 0, sent: 1, completed: 2, failed: 3 }

  validates :correlation_id, presence: true, uniqueness: true
  validates :idempotency_key, presence: true
  validates :action, presence: true

  scope :dead_letter, -> { failed.where('retry_count >= ?', DEAD_LETTER_RETRY_THRESHOLD) }

  def dead_letter?
    failed? && retry_count >= DEAD_LETTER_RETRY_THRESHOLD
  end
end
