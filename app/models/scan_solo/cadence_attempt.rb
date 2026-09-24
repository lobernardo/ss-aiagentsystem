# RF-62: one immutable evidence row per scheduled cadence attempt. Rows are
# created up front for every step at enrollment time (`scheduled`), and
# ScanSolo::Cadence::AttemptEvidenceRecorder is the sole writer of a
# terminal `result` -- never updated a second time once terminal.
# == Schema Information
#
# Table name: scan_solo_cadence_attempts
#
#  id                 :bigint           not null, primary key
#  cadence_version    :integer          not null
#  external_error     :text
#  last_block_reason  :string
#  last_checked_at    :datetime
#  result             :integer          default("scheduled"), not null
#  scheduled_at       :datetime         not null
#  sent_at            :datetime
#  step               :integer          not null
#  template_reference :string           not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  enrollment_id      :bigint           not null
#  message_id         :bigint
#
# Indexes
#
#  index_scan_solo_cadence_attempts_on_enrollment_id           (enrollment_id)
#  index_scan_solo_cadence_attempts_on_enrollment_id_and_step  (enrollment_id,step) UNIQUE
#  index_scan_solo_cadence_attempts_on_message_id              (message_id)
#
# Foreign Keys
#
#  fk_rails_...  (enrollment_id => scan_solo_cadence_enrollments.id)
#  fk_rails_...  (message_id => messages.id)
#
class ScanSolo::CadenceAttempt < ApplicationRecord
  self.table_name = 'scan_solo_cadence_attempts'

  TERMINAL_RESULTS = %w[sent skipped failed cancelled].freeze

  belongs_to :enrollment, class_name: 'ScanSolo::CadenceEnrollment', inverse_of: :attempts

  belongs_to :message, optional: true

  enum result: { scheduled: 0, sent: 1, skipped: 2, failed: 3, cancelled: 4, dispatched: 5 }

  validates :step, presence: true, uniqueness: { scope: :enrollment_id }

  def terminal?
    TERMINAL_RESULTS.include?(result)
  end
end
