# RF-62: one immutable evidence row per scheduled cadence attempt. Rows are
# created up front for every step at enrollment time (`scheduled`), and
# ScanSolo::Cadence::AttemptEvidenceRecorder is the sole writer of a
# terminal `result` -- never updated a second time once terminal.
class ScanSolo::CadenceAttempt < ApplicationRecord
  self.table_name = 'scan_solo_cadence_attempts'

  TERMINAL_RESULTS = %w[sent skipped failed cancelled].freeze

  belongs_to :enrollment, class_name: 'ScanSolo::CadenceEnrollment', foreign_key: :enrollment_id, inverse_of: :attempts

  enum result: { scheduled: 0, sent: 1, skipped: 2, failed: 3, cancelled: 4 }

  validates :step, presence: true, uniqueness: { scope: :enrollment_id }

  def terminal?
    TERMINAL_RESULTS.include?(result)
  end
end
