# frozen_string_literal: true

require 'rails_helper'

# RNF-04: no secret in .env.example, API responses, logs or LLM payloads.
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'ScanSolo secret hygiene' do
  describe '.env.example' do
    let(:env_example) { Rails.root.join('.env.example').read }
    let(:scansolo_block) { env_example.split('## ScanSolo production').last }
    let(:assignments) do
      scansolo_block.lines.filter_map { |line| line.strip.match(/\A([A-Z0-9_]+)=(.*)\z/)&.captures }
    end

    it 'ships every ScanSolo variable without a value' do
      expect(assignments).not_to be_empty
      assignments.each { |name, value| expect(value).to eq(''), "expected #{name}= to be empty in .env.example" }
    end

    it 'ships the shared database and redis passwords without a value' do
      %w[POSTGRES_PASSWORD REDIS_PASSWORD].each do |name|
        expect(env_example).to match(/^#{name}=$/), "expected #{name}= to be empty in .env.example"
      end
    end
  end

  describe 'ScanSolo API views' do
    let(:views) { Dir.glob(Rails.root.join('app/views/api/v1/accounts/scan_solo/**/*.jbuilder')) }
    let(:credential_attribute) do
      /json\.(\w*(?:secret|password|api_key|access_key|signing|credential|scenario_url|bearer)\w*|\w*_token)\b/i
    end

    it 'has views to check' do
      expect(views).not_to be_empty
    end

    it 'renders no credential-named attribute' do
      offending = views.flat_map { |path| File.read(path).scan(credential_attribute).flatten.map { |attr| "#{path}: #{attr}" } }

      expect(offending).to be_empty, "credential attributes rendered: #{offending.join(', ')}"
    end

    it 'never reads credentials or installation secrets directly' do
      offending = views.select { |path| File.read(path).match?(/credentials|InstallationConfig|ENV\[|ENV\.fetch/) }

      expect(offending).to be_empty, "views reading secrets: #{offending.join(', ')}"
    end
  end

  describe 'ScanSolo::AiTurn::PromptRedactor coverage' do
    let(:uuid) { '6f1c2a0e-4b7d-4e1a-9c3f-2d8e5b7a1c90' }

    it 'redacts API keys, bearer tokens and long opaque tokens but keeps UUIDs' do
      line = "turn #{uuid} key=sk-proj1234567890abcdefghij auth=Bearer abcdefghijklmnop token=#{'a1' * 20}"

      redacted = ScanSolo::AiTurn::PromptRedactor.call(line)

      expect(redacted).to include(uuid)
      expect(redacted).not_to include('sk-proj1234567890abcdefghij')
      expect(redacted).not_to include('Bearer abcdefghijklmnop')
      expect(redacted).not_to include('a1' * 20)
    end

    it 'redacts nested hash and array payloads' do
      payload = { messages: [{ content: 'use sk-live_abcdefgh12345678' }], meta: { secret: 'Bearer zzzzzzzzzzzzzzzz' } }

      expect(ScanSolo::AiTurn::PromptRedactor.call(payload).to_s).not_to match(/sk-live_abcdefgh12345678|Bearer zzzz/)
    end

    it 'is wired into the log formatter and the prompt payload builder' do
      expect(Rails.root.join('config/initializers/scansolo_log_redaction.rb').read).to include('ScanSolo::AiTurn::PromptRedactor.call')
      expect(Rails.root.join('app/services/scan_solo/ai_turn/prompt_builder.rb').read).to include('ScanSolo::AiTurn::PromptRedactor.call')
    end
  end

  describe 'Make outbound request evidence' do
    it 'never stores the Make secret in the persisted request payload' do
      account = create(:account, scansolo_enabled: true)
      secret = 'make-outbound-secret-value'
      scenario_url = 'https://hook.make.example/scenario-webhook'
      allow(Rails.application.credentials).to receive(:dig).with(:scan_solo, :make, :scenario_url).and_return(scenario_url)
      allow(Rails.application.credentials).to receive(:dig).with(:scan_solo, :make, :secret).and_return(secret)
      stub_request(:post, scenario_url).to_return(status: 200)

      request = ScanSolo::Make::OutboundRequestService.call(account: account, action: 'proposal.generate', payload: { proposal_version_id: 1 })

      expect(request.reload.attributes.to_json).not_to include(secret)
    end
  end
end
# rubocop:enable RSpec/DescribeClass
