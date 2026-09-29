json.partial! 'api/v1/accounts/scan_solo/pipeline_opportunities/pipeline_opportunity', resource: @opportunity
json.lead_state do
  json.partial! 'api/v1/accounts/scan_solo/pipeline_opportunities/lead_state', lead_state: @lead_state
end
