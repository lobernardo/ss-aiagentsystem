# RNF-06 / RF-85 / RF-86: one immutable row per inbound Make callback
# attempt (accepted or rejected), written only by
# Webhooks::ScanSolo::MakeController (T68). The permanent unique index on
# `correlation_id` (no TTL/expiry) is the entire replay-protection
# mechanism -- a repeated correlation id can never be inserted a second
# time, so a replayed callback is rejected indefinitely. `correlation_id`
# is nullable because a malformed (non-JSON) callback body has none to
# extract, yet RF-86 still requires it be recorded as an error row.
# == Schema Information
#
# Table name: scan_solo_make_callbacks
#
#  id               :bigint           not null, primary key
#  action           :string
#  applied          :boolean          default(FALSE), not null
#  payload          :jsonb            not null
#  rejection_reason :string
#  signature_valid  :boolean          default(FALSE), not null
#  created_at       :datetime         not null
#  correlation_id   :string
#
# Indexes
#
#  index_scan_solo_make_callbacks_on_correlation_id  (correlation_id) UNIQUE
#
class ScanSolo::MakeCallback < ApplicationRecord
  self.table_name = 'scan_solo_make_callbacks'

  validates :correlation_id, uniqueness: true, allow_nil: true

  def readonly?
    persisted?
  end
end
