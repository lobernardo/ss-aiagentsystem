json.array! @enrollments do |enrollment|
  json.partial! 'api/v1/accounts/scan_solo/cadence_enrollments/cadence_enrollment', resource: enrollment
end
