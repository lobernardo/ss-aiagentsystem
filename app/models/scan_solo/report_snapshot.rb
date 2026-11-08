# RF-13/CT-05: the frozen weekly report (CT-01 body for period=week) of an
# account. One row per (account, week_start); the weekly job upserts it and the
# reports endpoint serves it for closed weeks.
# == Schema Information
#
# Table name: scan_solo_report_snapshots
#
#  id           :bigint           not null, primary key
#  generated_at :datetime         not null
#  payload      :jsonb            not null
#  week_start   :date             not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :bigint           not null
#
# Indexes
#
#  index_scan_solo_report_snapshots_on_account_id_and_week_start  (account_id,week_start) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class ScanSolo::ReportSnapshot < ApplicationRecord
  self.table_name = 'scan_solo_report_snapshots'

  belongs_to :account

  validates :week_start, :payload, :generated_at, presence: true
  validates :week_start, uniqueness: { scope: :account_id }
end
