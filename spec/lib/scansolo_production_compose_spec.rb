require 'rails_helper'
require 'open3'

# Config checks for the ScanSolo production compose (RF-52..RF-55) rather than
# a spec for a single class.
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'ScanSolo production compose' do
  let(:compose_files) { %w[docker-compose.production.yaml docker-compose.scansolo.yaml] }
  let(:compose_sources) { compose_files.map { |file| Rails.root.join(file).read } }
  let(:env_example) { Rails.root.join('.env.example').read }
  let(:env_example_values) do
    env_example.lines.filter_map { |line| line.strip.match(/\A([A-Z0-9_]+)=(.*)\z/)&.captures }.to_h
  end

  describe 'rendered production config', if: system('docker compose version > /dev/null 2>&1') do
    let(:rendered) do
      output, status = Open3.capture2e(
        'docker', 'compose', *compose_files.flat_map { |file| ['-f', file] }, 'config', '--no-interpolate',
        chdir: Rails.root.to_s
      )
      raise "docker compose config failed:\n#{output}" unless status.success?

      output
    end
    let(:services) { YAML.safe_load(rendered)['services'] }

    it 'interpolates the postgres password from the environment' do
      expect(services['postgres']['environment']).to include('POSTGRES_PASSWORD=${POSTGRES_PASSWORD}')
    end

    it 'publishes ports only on the loopback address' do
      ports = services.values.flat_map { |service| service['ports'] || [] }

      expect(ports).not_to be_empty
      expect(ports.pluck('host_ip').uniq).to eq(['127.0.0.1'])
    end

    it 'runs no dev, proxy or storage service outside a profile' do
      unprofiled = services.reject { |_name, service| service['profiles'] }

      unprofiled.each do |name, service|
        expect("#{name} #{service['image']}").not_to match(/vite|mailhog|caddy|minio/)
      end
    end

    it 'mounts no source tree path' do
      volumes = services.values.flat_map { |service| service['volumes'] || [] }

      expect(volumes.pluck('type').uniq).to eq(['volume'])
    end

    it 'pins every pulled image to an explicit tag' do
      images = services.values.reject { |service| service['build'] }.map { |service| service['image'] }

      images.each do |image|
        expect(image).to match(/:[^:]+\z/), "expected #{image} to have a tag"
        expect(image).not_to end_with(':latest')
        expect(image).not_to eq('redis:alpine')
      end
    end
  end

  it 'drops the obsolete compose version key' do
    compose_sources.each { |source| expect(source).not_to match(/^version:/) }
  end

  it 'documents only the production plus overlay command' do
    expect(compose_sources.join).not_to include('-f docker-compose.yaml')
  end

  it 'writes the git sha from a required build argument' do
    dockerfile = Rails.root.join('docker/Dockerfile').read

    expect(dockerfile).not_to include('git rev-parse')
    expect(dockerfile).to include('ARG GIT_SHA')
    expect(dockerfile).to include('RUN test -n "$GIT_SHA" && echo "$GIT_SHA" > /app/.git_sha')
  end

  it 'keeps .git out of the build context' do
    expect(Rails.root.join('.dockerignore').read.lines.map(&:strip)).to include('.git')
  end

  it 'lists every compose variable empty in .env.example' do
    compose_vars = compose_sources.join.scan(/(?<!\$)\$\{?([A-Z][A-Z0-9_]*)/).flatten.uniq

    expect(compose_vars).to include('POSTGRES_PASSWORD', 'REDIS_PASSWORD', 'SCANSOLO_IMAGE_TAG', 'GIT_SHA')
    compose_vars.each { |var| expect(env_example_values[var]).to eq(''), "expected #{var}= in .env.example" }
  end

  it 'lists the ScanSolo rate limit variables empty in .env.example' do
    %w[
      RATE_LIMIT_SCANSOLO_MAKE_CALLBACK RATE_LIMIT_SCANSOLO_KNOWLEDGE_WRITES
      RATE_LIMIT_SCANSOLO_RETRIEVAL_TESTS RATE_LIMIT_SCANSOLO_PUBLISH
    ].each { |var| expect(env_example_values[var]).to eq(''), "expected #{var}= in .env.example" }
  end
end
# rubocop:enable RSpec/DescribeClass
