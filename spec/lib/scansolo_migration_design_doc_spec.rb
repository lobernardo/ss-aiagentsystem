require 'rails_helper'

# RF-98: before cutover, a documented migration/cutover design must cover
# every listed continuity-data category with an explicit decision (migrate /
# re-derive / explicitly discard). RF-99: this is a documentation-only check
# -- it never touches a live Lexus system.
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'ScanSolo Lexus migration/cutover design document' do
  let(:doc_path) { Rails.root.join('docs/migration/SCANSOLO_LEXUS_CUTOVER_DESIGN.md') }
  let(:content) { File.read(doc_path) }

  let(:categories) do
    [
      'Contact identity',
      'Agent configuration',
      'Knowledge sources',
      'Active pipeline state',
      'Qualification fields',
      'Proposal state/reference',
      'Approved template mappings',
      'Cadence state / re-enrollment strategy',
      'Human ownership/handoff state'
    ]
  end

  let(:decision_pattern) { /\*\*Decision:\s*(Migrate|Re-derive|Explicitly discard)/i }

  it 'exists' do
    expect(File.exist?(doc_path)).to be(true)
  end

  it 'covers every RF-98 continuity-data category with a heading' do
    categories.each do |category|
      expect(content).to include(category), "expected the document to have a section for '#{category}'"
    end
  end

  it 'gives every category an explicit migrate/re-derive/discard decision line' do
    sections = content.split(/^### \d+\.\s+/).drop(1)

    expect(sections.length).to eq(categories.length)

    sections.each_with_index do |section, index|
      expect(section).to match(decision_pattern),
                         "expected an explicit Decision line for category ##{index + 1} (#{categories[index]})"
    end
  end

  it 'states that no implementation task writes against Lexus production' do
    expect(content).to match(/no\s+.*?(?:task|code)\s+.*?(?:live\s+)?(?:read\s+or\s+)?write\s+against\s+.*?Lexus/im)
  end

  it 'references the source inventory documents it is grounded in' do
    expect(content).to include('LEXUS_REFERENCE_MAP.md')
    expect(content).to include('RUNTIME_DATA_INVENTORY.md')
  end
end
# rubocop:enable RSpec/DescribeClass
