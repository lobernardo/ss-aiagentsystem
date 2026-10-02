# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'ScanSolo Pipeline Opportunities API centralized operation (CT-02)', type: :request do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:index_path) { "/api/v1/accounts/#{account.id}/scan_solo/pipeline_opportunities" }
  let(:definition) { ScanSolo::CadenceDefinition.create!(stage: 'novo_lead', version: 1, offsets: [2, 24]) }

  def create_opportunity(stage: :novo_lead, lead_source: nil)
    contact = create(:contact, account: account)
    conversation = create(:conversation, account: account, contact: contact)
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: stage, lead_source: lead_source)
  end

  def create_full_opportunity
    opportunity = create_opportunity(lead_source: 'website')
    ScanSolo::LeadState::Writer.new(lead_state: opportunity.lead_state)
                               .apply_field!(key: 'empresa', value: 'Solar Ltda', status: 'confirmado', source_message_id: nil)
    ScanSolo::QuoteRequest.create!(account: account, opportunity: opportunity, correlation_id: SecureRandom.uuid, sent_at: Time.current)
    ScanSolo::Proposal.create!(opportunity: opportunity).versions.create!(status: :generated, value: 1000, currency: 'BRL')
    ScanSolo::ConversationExtension.resolve_for(opportunity.conversation).update!(ai_control_state: :human_active)
    ScanSolo::Cadence::EnrollmentService.call(opportunity: opportunity, cadence_definition: definition)
    opportunity
  end

  def index_query_count
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name].in?(%w[SCHEMA TRANSACTION]) || payload[:cached] }
    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') do
      get index_path, headers: agent.create_new_auth_token, as: :json
    end
    expect(response).to have_http_status(:success)
    count
  end

  describe 'GET .../pipeline_opportunities' do
    it 'runs the same number of queries with 5 and 50 fully loaded opportunities (RNF-06)' do
      5.times { create_full_opportunity }
      get index_path, headers: agent.create_new_auth_token, as: :json
      five = index_query_count

      45.times { create_full_opportunity }
      fifty = index_query_count

      expect(response.parsed_body.size).to eq(50)
      expect(fifty).to eq(five)
    end

    it 'exposes the new card fields' do
      opportunity = create_full_opportunity
      next_attempt_at = opportunity.cadence_enrollments.active.minimum(:next_attempt_at)

      get index_path, headers: agent.create_new_auth_token, as: :json

      item = response.parsed_body.first
      expect(item).to include(
        'lead_source' => 'website', 'company' => 'Solar Ltda', 'service' => nil, 'city_uf' => nil,
        'ai_control_state' => 'human_active', 'quote_request_status' => 'awaiting_reply', 'proposal_status' => 'generated'
      )
      expect(Time.zone.parse(item['next_follow_up_at'])).to be_within(1.second).of(next_attempt_at)
    end

    it 'defaults the bare opportunity fields: faltante company is null, no extension is ai_active' do
      create_opportunity

      get index_path, headers: agent.create_new_auth_token, as: :json

      expect(response.parsed_body.first).to include(
        'lead_source' => nil, 'company' => nil, 'service' => nil, 'city_uf' => nil, 'ai_control_state' => 'ai_active',
        'quote_request_status' => nil, 'proposal_status' => nil, 'next_follow_up_at' => nil
      )
    end
  end

  describe 'GET .../pipeline_opportunities/:id' do
    let(:opportunity) { create_opportunity(stage: :qualificado, lead_source: 'manual') }
    let(:show_path) { "#{index_path}/#{opportunity.id}" }

    it 'renders quote_request, proposal (stored document, not the Make artifact) and no template failure' do
      quote_request = ScanSolo::QuoteRequest.create!(account: account, opportunity: opportunity, correlation_id: SecureRandom.uuid,
                                                     sent_at: Time.current)
      version = ScanSolo::Proposal.create!(opportunity: opportunity).versions.create!(
        status: :generated, value: 1500, currency: 'BRL', artifact_url: 'https://make.test/a.pdf', valid_until: 15.days.from_now
      )
      version.document.attach(io: StringIO.new('%PDF-1.4'), filename: 'proposta.pdf', content_type: 'application/pdf')

      get show_path, headers: agent.create_new_auth_token, as: :json

      body = response.parsed_body
      expect(body['quote_request']).to include('id' => quote_request.id, 'status' => 'awaiting_reply', 'replied_at' => nil,
                                               'email_conversation_id' => nil)
      expect(body['proposal']).to include('version_number' => 1, 'proposal_number' => version.reload.proposal_number,
                                          'status' => 'generated', 'currency' => 'BRL', 'failure_reason' => nil)
      expect(body['proposal']['valid_until']).to be_present
      expect(body['proposal']['document_url']).to include('proposta.pdf')
      expect(body['proposal']['document_url']).not_to eq('https://make.test/a.pdf')
      expect(body['initial_template_failure']).to be_nil
    end

    it 'renders null quote_request and proposal when there are none' do
      get show_path, headers: agent.create_new_auth_token, as: :json

      expect(response.parsed_body).to include('quote_request' => nil, 'proposal' => nil, 'initial_template_failure' => nil)
    end

    it 'renders a blocked initial template with the guard reason (RF-08)' do
      ScanSolo::AuditLogger.record!(subject: opportunity, event_type: 'pipeline.manual_lead_template_blocked', correlation_id: SecureRandom.uuid,
                                    payload: { reason: 'template_missing' })

      get show_path, headers: agent.create_new_auth_token, as: :json

      failure = response.parsed_body['initial_template_failure']
      expect(failure).to include('status' => 'blocked', 'reason' => 'template_missing')
      expect(failure['occurred_at']).to be_present
    end

    it 'renders a failed initial template with the native external error (RF-08)' do
      ScanSolo::AuditLogger.record!(subject: opportunity, event_type: 'pipeline.manual_lead_template_failed', correlation_id: SecureRandom.uuid,
                                    payload: { message_id: 1, external_error: '131026: Message undeliverable' })

      get show_path, headers: agent.create_new_auth_token, as: :json

      expect(response.parsed_body['initial_template_failure']).to include('status' => 'failed', 'reason' => '131026: Message undeliverable')
    end

    it 'renders legacy fixtures without errors and with the current fields unchanged (RNF-10)' do
      approved_at = 2.days.ago.change(usec: 0)
      version = ScanSolo::Proposal.create!(opportunity: opportunity).versions.create!(
        status: :approved, approved_at: approved_at, value: 900, currency: 'BRL', artifact_url: 'https://make.test/legacy.pdf',
        send_correlation_id: 'legacy-send'
      )
      ScanSolo::MakeCallback.create!(correlation_id: 'legacy-send', action: 'proposal.send', payload: {}, applied: true, signature_valid: true)

      get show_path, headers: agent.create_new_auth_token, as: :json

      body = response.parsed_body
      expect(response).to have_http_status(:success)
      expect(body).to include('id' => opportunity.id, 'stage' => 'qualificado', 'contact_id' => opportunity.contact_id,
                              'conversation_id' => opportunity.conversation_id, 'proposal_status' => 'approved')
      expect(body['proposal']).to include('status' => 'approved', 'document_url' => nil, 'proposal_number' => version.reload.proposal_number)
    end
  end
end
