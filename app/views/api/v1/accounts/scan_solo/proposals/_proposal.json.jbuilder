json.id resource.id
json.opportunity_id resource.opportunity_id
json.owner_id resource.opportunity.owner_id
json.contact_name resource.opportunity.contact.name
json.integration_state ScanSolo::Proposal::Integration.state
json.current_version_id resource.current_version_id
json.versions resource.versions.order(:version_number) do |version|
  json.partial! 'api/v1/accounts/scan_solo/proposals/proposal_version', resource: version
end
# UI-05: status of the opportunity's quote request.
json.quote_request_status resource.opportunity.quote_request&.status
