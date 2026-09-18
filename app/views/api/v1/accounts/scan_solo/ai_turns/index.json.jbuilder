json.array! @turns do |turn|
  json.partial! 'api/v1/accounts/scan_solo/ai_turns/ai_turn', resource: turn
end
