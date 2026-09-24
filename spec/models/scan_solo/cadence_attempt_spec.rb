require 'rails_helper'

RSpec.describe ScanSolo::CadenceAttempt do
  it 'preserves existing result values and treats dispatched as nonterminal' do
    expect(described_class.results).to eq('scheduled' => 0, 'sent' => 1, 'skipped' => 2, 'failed' => 3, 'cancelled' => 4, 'dispatched' => 5)
    expect(described_class.new(result: :dispatched)).not_to be_terminal
    expect(described_class.reflect_on_association(:message).options[:optional]).to be true
  end
end
