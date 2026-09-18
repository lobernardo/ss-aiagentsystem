# A chunk of indexed knowledge content plus its pgvector embedding, via the
# `neighbor` gem directly (RF-28) — never through an enterprise-owned model.
# Every chunk is traceable back to its originating ScanSolo::KnowledgeSource
# for retrieval evidence (RF-29).
# == Schema Information
#
# Table name: scan_solo_knowledge_chunks
#
#  id         :bigint           not null, primary key
#  content    :text             not null
#  embedding  :vector(1536)
#  position   :integer          default(0), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  source_id  :bigint           not null
#
# Indexes
#
#  index_scan_solo_knowledge_chunks_on_source_id  (source_id)
#
# Foreign Keys
#
#  fk_rails_...  (source_id => scan_solo_knowledge_sources.id)
#
class ScanSolo::KnowledgeChunk < ApplicationRecord
  self.table_name = 'scan_solo_knowledge_chunks'

  belongs_to :source, class_name: 'ScanSolo::KnowledgeSource', inverse_of: :knowledge_chunks
  has_neighbors :embedding, normalize: true

  validates :content, presence: true
end
