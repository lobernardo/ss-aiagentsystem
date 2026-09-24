json.array! @rows do |row|
  json.partial! 'api/v1/accounts/scan_solo/cadence_templates/row', row: row
end
