# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Quote::RequestEmail::Settings do
  let(:valid_data) { YAML.safe_load_file(described_class::PATH) }

  describe 'the versioned file (RF-21, CT-05 (2))' do
    subject(:settings) { described_class.load }

    it 'maps GeoRadar and Pipe Locator terms (RF-04)' do
      expect(settings.service_labels.map { |entry| [entry.label, entry.terms] }).to eq(
        [
          ['GeoRadar', ['georadar', 'geo radar', 'gpr']],
          ['Pipe Locator', ['pipe locator', 'pipelocator', 'localizador de tubulação']]
        ]
      )
      expect(settings.combined_label).to eq('GeoRadar + Pipe Locator')
    end

    it 'has exactly the 4 service keys, each with the 8 CT-07 items in order' do
      expect(valid_data['pending_items_by_service'].keys).to eq(['GeoRadar', 'Pipe Locator', 'GeoRadar + Pipe Locator', 'outro'])

      described_class::SERVICE_KEYS.each do |service_key|
        expect(settings.pending_indexes(service_key)).to eq([1, 2, 3, 4, 5, 6, 7, 8])
      end
    end

    it 'is loaded once' do
      expect(described_class.load).to be(settings)
    end

    it 'fails loudly for a service key outside the table' do
      expect { settings.pending_indexes('Sondagem') }.to raise_error(KeyError)
    end
  end

  describe 'invalid files' do
    it 'rejects an extra service key' do
      valid_data['pending_items_by_service']['Sondagem'] = [1]

      expect { described_class.new(valid_data) }.to raise_error(ArgumentError, /Sondagem/)
    end

    it 'rejects a missing service key' do
      valid_data['pending_items_by_service'].delete('outro')

      expect { described_class.new(valid_data) }.to raise_error(ArgumentError, /outro/)
    end

    it 'rejects a pending index outside 1..8' do
      valid_data['pending_items_by_service']['GeoRadar'] = [1, 9]

      expect { described_class.new(valid_data) }.to raise_error(ArgumentError, /GeoRadar/)
    end

    it 'rejects a repeated pending index' do
      valid_data['pending_items_by_service']['Pipe Locator'] = [2, 2]

      expect { described_class.new(valid_data) }.to raise_error(ArgumentError, /Pipe Locator/)
    end

    %w[service_labels combined_label pending_items_by_service].each do |key|
      it "rejects a file without #{key}" do
        valid_data.delete(key)

        expect { described_class.new(valid_data) }.to raise_error(ArgumentError, /#{key}/)
      end
    end

    it 'rejects a service label outside the table' do
      valid_data['service_labels'] << { 'label' => 'Sondagem', 'terms' => ['spt'] }

      expect { described_class.new(valid_data) }.to raise_error(ArgumentError, /Sondagem/)
    end
  end

  it 'keeps the pending table out of the published config and the draft (RF-21)' do
    expect(ScanSolo::AiAgentConfig.column_names.grep(/pending|service_label/)).to be_empty
    expect(ScanSolo::AiAgentConfig::FIELDS.grep(/pending|service_label/)).to be_empty
  end
end
