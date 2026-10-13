require 'rails_helper'

RSpec.describe ScanSolo::Proposal::Integration do
  let(:account) { create(:account) }

  before do
    allow(Rails.application.credentials).to receive(:dig).with(:scan_solo, :make, anything).and_return(nil)
  end

  it 'reports the integration as blocked without all three credentials' do
    expect(described_class).not_to be_configured
    expect(described_class.state(account)).to eq('blocked')
    allow(Rails.application.credentials).to receive(:dig).with(:scan_solo, :make, :scenario_url).and_return('https://make.example.test')
    allow(Rails.application.credentials).to receive(:dig).with(:scan_solo, :make, :secret).and_return('outbound-secret')
    expect(described_class).not_to be_configured
  end

  it 'uses Make when configured, including in development or test' do
    allow(Rails.application.credentials).to receive(:dig).with(:scan_solo, :make, anything).and_return('configured')
    expect(described_class.state(account)).to eq('configured')
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

  describe 'local mode (RF-01, RF-19, CT-08, CT-09)' do
    let(:other_account) { create(:account) }

    before do
      allow(Rails.application.credentials).to receive(:dig).with(:scan_solo, :make, anything).and_return('configured')
      ScanSolo::ProposalTemplate.new(account: account, filename: 'proposta.docx', byte_size: 7, sha256: 'a' * 64, active: true).tap do |record|
        record.file.attach(io: StringIO.new('PK-docx'), filename: 'proposta.docx')
        record.save!
      end
    end

    it 'selects the local provider over the Make credentials' do
      with_modified_env(SCANSOLO_GOTENBERG_URL: 'http://gotenberg.test:3000') do
        expect(described_class).to be_local
        expect(described_class.provider!).to eq(ScanSolo::Proposal::LocalProvider)
      end
    end

    it 'keeps Make without the variable or with it blank' do
      with_modified_env(SCANSOLO_GOTENBERG_URL: '') do
        expect(described_class).not_to be_local
        expect(described_class.provider!).to eq(ScanSolo::Proposal::MakeProvider)
      end
    end

    it 'computes the state per account from the active template' do
      with_modified_env(SCANSOLO_GOTENBERG_URL: 'http://gotenberg.test:3000') do
        expect(described_class.state(account)).to eq('configured')
        expect(described_class.state(other_account)).to eq('blocked')
      end
    end

    it 'is blocked when the account only has an inactive template' do
      ScanSolo::ProposalTemplate.active_for(account).update!(active: false)

      with_modified_env(SCANSOLO_GOTENBERG_URL: 'http://gotenberg.test:3000') do
        expect(described_class.state(account)).to eq('blocked')
      end
    end
  end
end
