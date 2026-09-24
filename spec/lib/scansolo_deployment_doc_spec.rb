require 'rails_helper'

# Documentation checks for the ScanSolo deploy runbook (RF-52, RF-56, RF-57)
# rather than a spec for a single class.
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'ScanSolo deployment documentation' do
  let(:content) { Rails.root.join('docs/architecture/SCANSOLO_DEPLOYMENT.md').read }
  let(:commands) { content.scan(/```sh\n(.*?)```/m).flatten.join("\n") }
  let(:steps) { content.scan(/^### Step (\d) — (.+)$/) }

  it 'lists the 9 deploy steps in order' do
    expect(steps.map(&:first)).to eq(%w[1 2 3 4 5 6 7 8 9])
    expect(steps.map(&:last)).to match([
                                         /Diff the VPS compose and \.env names against Git/,
                                         /Back up the database and check the dump size/,
                                         /Build the image with GIT_SHA and a new SCANSOLO_IMAGE_TAG/,
                                         /Run migrations/,
                                         /Load the cadence definitions/,
                                         /Restart Rails/,
                                         /Restart Sidekiq/,
                                         /Run the smoke check/,
                                         /Rollback/
                                       ])
  end

  it 'uses the backup profile, the new tag, the cadence loader and the smoke task' do
    expect(commands).to include('--profile backup run --rm backup')
    expect(commands).to include('export GIT_SHA=', 'export SCANSOLO_IMAGE_TAG=')
    expect(commands).to include('rails db:migrate', 'scansolo:load_cadence_definitions', 'scansolo:smoke[')
  end

  it 'rolls back with the previous tag, a restart and a restore command' do
    rollback = content.split('### Step 9 — Rollback').last.split(/^## /).first

    expect(rollback).to include('SCANSOLO_IMAGE_TAG=$PREVIOUS_SCANSOLO_IMAGE_TAG', 'up -d --no-deps rails sidekiq')
    expect(rollback).to match(/gunzip -c .*\| psql/)
  end

  it 'only uses the production plus overlay compose command' do
    compose_commands = commands.scan(/docker compose.*$/)

    expect(compose_commands).not_to be_empty
    expect(compose_commands).to all(include('-f docker-compose.production.yaml -f docker-compose.scansolo.yaml'))
    expect(content).not_to include('-f docker-compose.yaml')
  end

  it 'has no Nginx, certificate or reverse proxy command' do
    expect(commands).not_to match(/nginx|certbot|--profile reverse-proxy|--profile self-hosted-storage/i)
  end

  it 'restarts Rails and Sidekiq after saving or rotating the OpenAI key' do
    rotation = content.split('## OpenAI key rotation').last.split(/^## /).first

    expect(rotation).to include('CAPTAIN_OPEN_AI_API_KEY', 'restart rails sidekiq')
  end

  it 'states that pre-cutover setup runs with the flag on and an empty inbox allowlist' do
    expect(content).to include('scansolo_enabled')
    expect(content).to match(/flag \*\*on\*\* and an \*\*empty\s+inbox allowlist\*\*/)
  end
end
# rubocop:enable RSpec/DescribeClass
