# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Notifications::NegotiationPayload do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, name: 'Ana Souza', phone_number: '+5511987654321') }
  let(:inbox) { create(:inbox, account: account, channel: create(:channel_api, account: account)) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :negociacao)
  end
  let(:correlation_id) { SecureRandom.uuid }
  let(:trigger) { create(:message, account: account, conversation: conversation, message_type: :incoming, content: 'Consegue 10% de desconto?') }
  let(:schema) do
    asyncapi = YAML.safe_load_file(Rails.root.join('.spec/features/scansolo-operacao-centralizada/asyncapi.yaml'))
    JSONSchemer.schema(asyncapi.dig('components', 'schemas', 'NegotiationRequestedPayload').merge('components' => asyncapi['components']))
  end

  around { |example| with_modified_env(FRONTEND_URL: 'https://app.example.com') { example.run } }

  def build
    described_class.build(opportunity: opportunity, trigger_message: trigger, correlation_id: correlation_id)
  end

  it 'builds the CT-07 payload with the current proposal and value' do
    ScanSolo::LeadState::Writer.new(lead_state: opportunity.lead_state)
                               .apply_field!(key: 'empresa', value: 'Solar Ltda', status: 'confirmado', source_message_id: nil)
    version = ScanSolo::Proposal.create!(opportunity: opportunity).versions.create!(
      generate_correlation_id: SecureRandom.uuid, status: :sent, value: 12_500, currency: 'BRL'
    )
    version.document.attach(io: StringIO.new('%PDF-1.4'), filename: 'proposta.pdf', content_type: 'application/pdf')

    payload = build

    expect(payload).to include(
      account_id: account.id, opportunity_id: opportunity.id, conversation_id: conversation.id,
      conversation_url: "https://app.example.com/app/accounts/#{account.id}/conversations/#{conversation.display_id}",
      contact: { name: 'Ana Souza', company: 'Solar Ltda', phone: '+5511987654321' }, stage: 'negociacao',
      request_summary: 'Consegue 10% de desconto?', correlation_id: correlation_id,
      proposal: { version_number: 1, proposal_number: version.reload.proposal_number, status: 'sent', document_url: version.document_url },
      current_value: { amount: 12_500.0, currency: 'BRL' }
    )
    expect(schema.validate(JSON.parse(payload.to_json)).to_a).to be_empty
  end

  it 'sends a null proposal and value without a proposal' do
    payload = build

    expect(payload).to include(proposal: nil, current_value: nil, contact: include(company: nil))
    expect(schema.valid?(JSON.parse(payload.to_json))).to be(true)
  end

  it 'keeps the last 3 chat messages in order, skipping private notes and activities' do
    create(:message, account: account, conversation: conversation, message_type: :incoming, content: 'primeira')
    create(:message, account: account, conversation: conversation, message_type: :outgoing, content: 'segunda')
    trigger
    create(:message, account: account, conversation: conversation, message_type: :outgoing, content: 'nota', private: true)
    create(:message, account: account, conversation: conversation, message_type: :activity, content: 'atividade')

    messages = build[:recent_messages]

    expect(messages.pluck(:sender, :content)).to eq([%w[customer primeira], %w[agent segunda], ['customer', 'Consegue 10% de desconto?']])
    expect(messages).to all(include(created_at: be_a(String)))
  end
end
