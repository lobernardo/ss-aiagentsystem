json.array! @opportunities do |opportunity|
  json.partial! 'api/v1/accounts/scan_solo/pipeline_opportunities/pipeline_opportunity', resource: opportunity,
                                                                                         next_follow_up_at: @next_follow_ups[opportunity.id]
end
