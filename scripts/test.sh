#!/usr/bin/env sh
set -eu

cd "$(dirname "$0")/.."

if command -v rbenv >/dev/null 2>&1; then
  eval "$(rbenv init -)"
fi

bundle exec ruby -e 'require "pdf-reader"; puts "pdf-reader #{Gem.loaded_specs.fetch("pdf-reader").version}"'

RAILS_ENV=test bundle exec rspec \
  spec/models/scan_solo/lead_state_spec.rb \
  spec/models/scan_solo/lead_state_event_spec.rb \
  spec/services/scan_solo/qualification/field_resolver_spec.rb \
  spec/services/scan_solo/ai_turn/model_invoker_spec.rb \
  spec/services/scan_solo/test_mode/mock_llm_provider_spec.rb \
  spec/services/scan_solo/lead_state/writer_spec.rb \
  spec/services/scan_solo/ai_turn/attachment_reader_spec.rb \
  spec/services/scan_solo/lead_state/initialize_service_spec.rb \
  spec/services/scan_solo/pipeline/opportunity_bootstrap_service_spec.rb \
  spec/services/scan_solo/lead_state/projection_spec.rb \
  spec/services/scan_solo/actions/lead_state_update_action_spec.rb \
  spec/services/scan_solo/actions/registry_spec.rb \
  spec/services/scan_solo/ai_turn/input_guardrail_spec.rb \
  spec/services/scan_solo/actions/qualification_field_action_spec.rb \
  spec/services/scan_solo/lead_state/completion_service_spec.rb \
  spec/services/scan_solo/ai_turn/context_assembler_spec.rb \
  spec/services/scan_solo/ai_turn/output_validator_spec.rb \
  spec/requests/api/v1/accounts/scan_solo/pipeline_opportunities_spec.rb \
  spec/requests/api/v1/accounts/scan_solo/pipeline_opportunities_lead_state_spec.rb \
  spec/services/scan_solo/qualification/consumer_consistency_spec.rb \
  spec/services/scan_solo/cadence/reply_completeness_detector_spec.rb \
  spec/services/scan_solo/proposal/generate_service_spec.rb \
  spec/services/scan_solo/proposal/make_provider_spec.rb \
  spec/services/scan_solo/handoff/handoff_service_spec.rb \
  spec/requests/api/v1/accounts/scan_solo/proposals_spec.rb

TZ=UTC vitest --no-watch --no-cache --no-coverage --logHeapUsage
