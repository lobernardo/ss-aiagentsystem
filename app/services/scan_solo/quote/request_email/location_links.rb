# RF-10 / RF-16: the Google Maps links of the quote request e-mail, from the
# chronological list of candidate URLs (lead state `link_local`, `location`
# attachments and map URLs of incoming messages). Pure: no HTTP, no I/O.
#
# - Coordinates from `q=`/`query=`/`ll=` or `@lat,lng` → normalized to
#   `https://www.google.com/maps?q={lat},{lng}` with 6 to 7 decimals (sign kept).
# - A point less than 50 m (haversine) from an accepted one is dropped; the
#   first received stays.
# - An `https` URL of a host accepted by AttachmentReader::MAP_URL_PATTERN
#   without coordinates (e.g. `maps.app.goo.gl/...`) is kept as is, never
#   expanded nor deduplicated.
# - A non-`https` URL or a host outside the pattern is dropped.
# The `Ponto N` labels are applied by the renderer.
class ScanSolo::Quote::RequestEmail::LocationLinks
  DEDUP_METERS = 50
  EARTH_RADIUS_METERS = 6_371_000
  NUMBER = '([-+]?\d{1,3}(?:\.\d+)?)'.freeze
  SEPARATOR = '(?:,|%2C)(?:\s|\+|%20)*'.freeze
  COORDINATE_PATTERNS = [
    /[?&](?:q|query|ll)=#{NUMBER}#{SEPARATOR}#{NUMBER}(?:[&#]|\z)/io,
    %r{@#{NUMBER},#{NUMBER}(?:[,/?#]|\z)}o
  ].freeze
  MIN_DECIMALS = 6
  MAX_DECIMALS = 7

  def self.call(sources:)
    points = []
    map_urls(sources).each_with_object([]) do |url, links|
      coordinates = coordinates(url)
      next links << url if coordinates.nil?

      point = coordinates.map(&:to_f)
      next if points.any? { |accepted| distance_meters(accepted, point) < DEDUP_METERS }

      points << point
      links << "https://www.google.com/maps?q=#{decimal(coordinates[0])},#{decimal(coordinates[1])}"
    end
  end

  # RF-16: only `https` URLs of a known map host can become links.
  def self.map_urls(sources)
    sources.map { |source| source.to_s.strip }
           .select { |url| url.match?(%r{\Ahttps://}i) && url.match?(ScanSolo::AiTurn::AttachmentReader::MAP_URL_PATTERN) }
  end

  def self.coordinates(url)
    COORDINATE_PATTERNS.each do |pattern|
      lat, lng = url.match(pattern)&.captures
      next if lat.nil?
      return [lat, lng] if lat.to_f.abs <= 90 && lng.to_f.abs <= 180
    end
    nil
  end

  # Keeps the received text when it already has 6 or 7 decimals; otherwise
  # rounds to 7 and drops trailing zeros down to 6.
  def self.decimal(value)
    value = value.delete_prefix('+')
    return value if value.split('.')[1].to_s.length.between?(MIN_DECIMALS, MAX_DECIMALS)

    format("%.#{MAX_DECIMALS}f", value.to_f).sub(/(\.\d{#{MIN_DECIMALS}}\d*?)0+\z/o, '\1')
  end

  def self.distance_meters((lat1, lng1), (lat2, lng2))
    d_lat = (lat2 - lat1) * Math::PI / 180
    d_lng = (lng2 - lng1) * Math::PI / 180
    a = (Math.sin(d_lat / 2)**2) + (Math.cos(lat1 * Math::PI / 180) * Math.cos(lat2 * Math::PI / 180) * (Math.sin(d_lng / 2)**2))
    2 * EARTH_RADIUS_METERS * Math.asin(Math.sqrt(a))
  end

  private_class_method :map_urls, :coordinates, :decimal, :distance_meters
end
