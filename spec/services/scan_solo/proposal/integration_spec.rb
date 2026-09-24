require 'rails_helper'

RSpec.describe ScanSolo::Proposal::Integration do
  before do
    allow(Rails.application.credentials).to receive(:dig).with(:scan_solo, :make, anything).and_return(nil)
  end

  it 'reports the integration as blocked without all three credentials' do
    expect(described_class).not_to be_configured
    expect(described_class.state).to eq('blocked')
    allow(Rails.application.credentials).to receive(:dig).with(:scan_solo, :make, :scenario_url).and_return('https://make.example.test')
    allow(Rails.application.credentials).to receive(:dig).with(:scan_solo, :make, :secret).and_return('outbound-secret')
    expect(described_class).not_to be_configured
  end

  it 'uses Make when configured, including in development or test' do
    allow(Rails.application.credentials).to receive(:dig).with(:scan_solo, :make, anything).and_return('configured')
    expect(described_class.state).to eq('configured')
    expect(described_class.provider!).to eq(ScanSolo::Proposal::MakeProvider)
  end

  it 'permits mock only in test and development' do
    %w[test development].each do |environment|
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new(environment))
      expect(described_class.provider!).to eq(ScanSolo::Proposal::MockProvider)
    end
  end

  it 'rejects production and other environments without credentials' do
    %w[production staging].each do |environment|
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new(environment))
      expect { described_class.provider! }.to raise_error do |error|
        expect(error.class.name).to eq('CustomExceptions::ScanSolo::ProposalIntegrationNotConfigured')
      end
    end
  end
end
