json.merge! ScanSolo::CadenceEnrollmentSerializer.new(resource).as_json
json.contact_name resource.opportunity.contact.name
json.cadence_stage resource.cadence_definition.stage
json.cadence_version resource.cadence_definition.version
