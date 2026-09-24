# Applied callbacks permanently reserve their correlation id; rejected attempts do not.
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
#  index_scan_solo_make_callbacks_on_correlation_id  (correlation_id) UNIQUE WHERE (applied = true)
#
class ScanSolo::MakeCallback < ApplicationRecord
  self.table_name = 'scan_solo_make_callbacks'

  scope :applied, -> { where(applied: true) }

  validates :correlation_id, uniqueness: { conditions: -> { applied } }, allow_nil: true, if: :applied?

  def readonly?
    persisted?
  end
end
