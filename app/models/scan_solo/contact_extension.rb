# == Schema Information
#
# Table name: scan_solo_contact_extensions
#
#  id               :bigint           not null, primary key
#  opted_out        :boolean          default(FALSE), not null
#  opted_out_at     :datetime
#  opted_out_source :string
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  contact_id       :bigint           not null
#
# Indexes
#
#  index_scan_solo_contact_extensions_on_contact_id  (contact_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (contact_id => contacts.id)
#
class ScanSolo::ContactExtension < ApplicationRecord
  self.table_name = 'scan_solo_contact_extensions'

  belongs_to :contact

  validates :contact_id, uniqueness: true

  def self.resolve_for(contact)
    find_or_create_by!(contact: contact)
  end

  def self.opted_out?(contact)
    exists?(contact: contact, opted_out: true)
  end
end
