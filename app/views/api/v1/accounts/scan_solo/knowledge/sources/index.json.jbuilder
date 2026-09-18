json.array! @sources do |source|
  json.partial! 'api/v1/accounts/scan_solo/knowledge/sources/source', resource: source
end
