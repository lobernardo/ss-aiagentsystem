# RF-04 / RF-08 / RF-21 / CT-05 (2): service label map and pending items per
# service type, read from the versioned `config/scan_solo/quote_request_email.yml`
# (outside the published config, no UI). Loaded once; a missing key, an unknown
# service key or a pending index outside 1..8 (or repeated) is a deployment bug
# and raises ArgumentError.
class ScanSolo::Quote::RequestEmail::Settings
  PATH = Rails.root.join('config/scan_solo/quote_request_email.yml')
  SERVICE_KEYS = ['GeoRadar', 'Pipe Locator', 'GeoRadar + Pipe Locator', 'outro'].freeze
  PENDING_INDEXES = (1..8)

  ServiceLabel = Struct.new(:label, :terms, keyword_init: true)

  attr_reader :service_labels, :combined_label

  def self.load
    @load ||= new(YAML.safe_load_file(PATH))
  end

  def initialize(data)
    @service_labels = fetch!(data, 'service_labels').map do |entry|
      ensure_service_key!(entry['label'])
      ServiceLabel.new(label: entry['label'], terms: entry['terms']).freeze
    end.freeze
    @combined_label = ensure_service_key!(fetch!(data, 'combined_label'))
    @pending_items_by_service = build_pending_items(fetch!(data, 'pending_items_by_service'))
  end

  def pending_indexes(service_key)
    @pending_items_by_service.fetch(service_key)
  end

  private

  def fetch!(data, key)
    data.fetch(key) { raise ArgumentError, "quote_request_email settings missing key: #{key}" }
  end

  def ensure_service_key!(label)
    raise ArgumentError, "unknown service label: #{label.inspect}" unless SERVICE_KEYS.include?(label)

    label
  end

  def build_pending_items(map)
    missing = SERVICE_KEYS - map.keys
    raise ArgumentError, "missing pending service keys: #{missing.join(', ')}" if missing.any?

    map.to_h do |service_key, indexes|
      ensure_service_key!(service_key)
      valid = indexes.uniq == indexes && indexes.all? { |index| PENDING_INDEXES.include?(index) }
      raise ArgumentError, "invalid pending indexes for #{service_key}: #{indexes.inspect}" unless valid

      [service_key, indexes.freeze]
    end.freeze
  end
end
