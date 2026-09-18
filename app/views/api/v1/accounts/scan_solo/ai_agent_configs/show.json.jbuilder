json.draft do
  json.partial! 'api/v1/accounts/scan_solo/ai_agent_configs/ai_agent_config', resource: @draft
end
json.published do
  if @published
    json.partial! 'api/v1/accounts/scan_solo/ai_agent_configs/ai_agent_config', resource: @published
  else
    json.null!
  end
end
