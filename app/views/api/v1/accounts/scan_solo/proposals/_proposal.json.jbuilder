json.id resource.id
json.opportunity_id resource.opportunity_id
json.contact_name resource.opportunity.contact.name
json.current_version_id resource.current_version_id
json.versions resource.versions.order(:version_number) do |version|
  json.partial! 'api/v1/accounts/scan_solo/proposals/proposal_version', resource: version
end
