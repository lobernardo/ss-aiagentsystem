class ScanSolo::ContactExtension < ApplicationRecord
  self.table_name = 'scan_solo_contact_extensions'

  belongs_to :contact

  validates :contact_id, uniqueness: true

  def self.resolve_for(contact)
    find_or_create_by!(contact: contact)
  end
end
