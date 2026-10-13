# CT-06, RF-17, RF-21: the `.docx` proposal template of an account, stored in
# ActiveStorage (`file`). At most one active template per account (partial
# unique index); inactive templates are history and are never deleted.
# Reads are always scoped by account (`active_for`).
# == Schema Information
#
# Table name: scan_solo_proposal_templates
#
#  id             :bigint           not null, primary key
#  active         :boolean          default(FALSE), not null
#  byte_size      :bigint           not null
#  filename       :string           not null
#  sha256         :string           not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  account_id     :bigint           not null
#  uploaded_by_id :bigint
#
# Indexes
#
#  index_scan_solo_proposal_templates_on_account_and_created_at  (account_id,created_at)
#  index_scan_solo_proposal_templates_one_active_per_account     (account_id) UNIQUE WHERE active
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (uploaded_by_id => users.id) ON DELETE => nullify
#
class ScanSolo::ProposalTemplate < ApplicationRecord
  self.table_name = 'scan_solo_proposal_templates'

  belongs_to :account
  belongs_to :uploaded_by, class_name: 'User', optional: true
  has_one_attached :file

  validates :filename, :byte_size, :sha256, presence: true
  validates :sha256, format: { with: /\A\h{64}\z/ }, allow_blank: true
  validate :file_attached

  scope :active, -> { where(active: true) }

  def self.active_for(account)
    active.find_by(account: account)
  end

  # RF-10, CT-07: identifies the exact template bytes used by a generation.
  def template_version
    "#{id}:#{sha256}"
  end

  private

  def file_attached
    errors.add(:file, :blank) unless file.attached?
  end
end
