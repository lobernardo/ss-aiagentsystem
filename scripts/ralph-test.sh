#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

COMPOSE=(
  docker compose
  -f docker-compose.yaml
  -f local/docker-compose.override.yml
)

echo "==> Checking Docker services"
"${COMPOSE[@]}" exec -T rails true
"${COMPOSE[@]}" exec -T vite true

echo "==> Preparing test database"
"${COMPOSE[@]}" exec -T -e RAILS_ENV=test rails \
  bundle exec rails db:test:prepare

echo "==> Running ScanSolo Ruby specs"

ruby_specs=("spec/models/account_spec.rb")

while IFS= read -r file; do
  already_added=false
  for existing in "${ruby_specs[@]}"; do
    if [[ "$existing" == "$file" ]]; then
      already_added=true
      break
    fi
  done

  if [[ "$already_added" == false ]]; then
    ruby_specs+=("$file")
  fi
done < <(
  find spec -type f \
    \( -path '*scan_solo*' -o -name '*scansolo*_spec.rb' \) \
    | sort
)

"${COMPOSE[@]}" exec -T -e RAILS_ENV=test rails \
  bundle exec rspec "${ruby_specs[@]}"

echo "==> Running ScanSolo frontend specs"

mapfile -t frontend_specs < <(
  find app/javascript/dashboard \
    -type f \
    -path '*scansolo*' \
    \( -name '*.spec.js' -o -name '*.spec.ts' \) \
    | sort
)

if (( ${#frontend_specs[@]} > 0 )); then
  "${COMPOSE[@]}" exec -T vite \
    pnpm test -- "${frontend_specs[@]}"
else
  echo "No ScanSolo frontend specs exist yet; skipping frontend test runner."
fi

echo "==> Ralph test gate passed"
