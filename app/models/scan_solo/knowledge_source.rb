# A knowledge entry (document upload, FAQ, or company/service info) plus the
# source metadata every entry must carry (RF-27): type, origin, added-by,
# timestamp. Disabling a source excludes its chunks from retrieval without
# deleting data (RF-30); document uploads go through the native ActiveStorage
# attachment mechanism, never a parallel unvalidated upload path (RF-90).
# == Schema Information
#
# Table name: scan_solo_knowledge_sources
#
#  id           :bigint           not null, primary key
#  chunk_count  :integer          default(0), not null
#  content      :text
#  enabled      :boolean          default(TRUE), not null
#  index_error  :text
#  index_status :integer          default("pending"), not null
#  indexed_at   :datetime
#  origin       :string
#  source_type  :integer          default("document"), not null
#  title        :string
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :bigint           not null
#  added_by_id  :bigint
#
# Indexes
#
#  index_scan_solo_knowledge_sources_on_account_id   (account_id)
#  index_scan_solo_knowledge_sources_on_added_by_id  (added_by_id)
#
class ScanSolo::KnowledgeSource < ApplicationRecord
  self.table_name = 'scan_solo_knowledge_sources'

  belongs_to :account
  belongs_to :added_by, class_name: 'User'
  has_many :knowledge_chunks,
           class_name: 'ScanSolo::KnowledgeChunk',
           foreign_key: :source_id,
           inverse_of: :source,
           dependent: :destroy
  has_one_attached :file

  enum source_type: { document: 0, faq: 1, company_info: 2 }

  enum index_status: { pending: 0, indexing: 1, indexed: 2, failed: 3 }

  validates :origin, presence: true
end
