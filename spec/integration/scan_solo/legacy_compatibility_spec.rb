# frozen_string_literal: true

require 'rails_helper'

# scansolo-operacao-centralizada T33 / RNF-10, RF-55 (Etapa 1): records written
# before the centralized operation -- opportunities with no `lead_source`,
# versions approved/sent by the legacy approve/send flow (no proposal number,
# no quote request, link only in the message fallback) and historical
# `proposal.send` Make requests/callbacks -- stay readable through every read
# API with 0 errors and their values unchanged.
#
# scansolo-proposta-aprovacao-email T32 / RF-26: a legacy `generated` version
# (code 1, never approved) joins the fixtures; the 0-4 status codes are kept
# and the new read fields (CT-01) come back empty for every legacy version.
RSpec.describe 'ScanSolo legacy records after the centralized operation', type: :request do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Cliente Antigo') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:base_path) { "/api/v1/accounts/#{account.id}/scan_solo" }
  let(:approved_at) { 40.days.ago.change(usec: 0) }
  let(:send_correlation_id) { SecureRandom.uuid }
  let!(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :proposta_enviada)
  end
  let!(:proposal) { ScanSolo::Proposal.create!(opportunity: opportunity) }
  let!(:generated_version) do
    proposal.versions.create!(status: :generated, value: 700, currency: 'BRL', artifact_url: 'https://make.example/legacy/0.pdf',
                              is_current: false)
  end
  let!(:approved_version) do
    proposal.versions.create!(status: :approved, approved_at: approved_at, approved_by: admin, value: 900, currency: 'BRL',
                              artifact_url: 'https://make.example/legacy/1.pdf', is_current: false)
  end
  let!(:sent_version) do
    proposal.versions.create!(status: :sent, approved_at: approved_at, value: 1200, currency: 'BRL', artifact_url: 'https://make.example/legacy/2.pdf',
                              send_correlation_id: send_correlation_id, send_requested_at: approved_at, send_callback_applied_at: approved_at,
                              sent_message: create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                                                             content: 'https://make.example/legacy/2.pdf',
                                                             additional_attributes: { 'scansolo_origin' => 'proposal' }))
  end

  before do
    ScanSolo::AiAgentConfig.draft_for!(account).update!(name: 'Agente', enabled: true, allowed_inbox_ids: [inbox.id],
                                                        require_proposal_approval: true)
    ScanSolo::AiAgent::PublishService.new(account: account).call
    # Pre-deploy rows: no lead source and no proposal number.
    opportunity.update_columns(lead_source: nil) # rubocop:disable Rails/SkipsModelValidations
    ScanSolo::ProposalVersion.where(id: [generated_version.id, approved_version.id, sent_version.id])
                             .update_all(proposal_number: nil) # rubocop:disable Rails/SkipsModelValidations
    writer = ScanSolo::LeadState::Writer.new(lead_state: opportunity.lead_state)
    writer.complete!(at: 50.days.ago)
    writer.record_next_action!(value: 'proposta', source_message_id: nil)
    ScanSolo::MakeRequest.create!(account: account, correlation_id: send_correlation_id, idempotency_key: send_correlation_id,
                                  action: 'proposal.send', status: :completed,
                                  payload: { opportunity_id: opportunity.id, proposal_version_id: sent_version.id })
    ScanSolo::MakeCallback.create!(correlation_id: send_correlation_id, action: 'proposal.send', applied: true, signature_valid: true,
                                   payload: { 'action' => 'proposal.send', 'status' => 'success',
                                              'result' => { 'proposal_version_id' => sent_version.id } })
  end

  def read(path, user = agent)
    get "#{base_path}/#{path}", headers: user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    response.parsed_body
  end

  it 'lists the legacy opportunity in the pipeline with an empty origin and no quote request (CT-02)' do
    item = read('pipeline_opportunities').find { |row| row['id'] == opportunity.id }

    expect(item).to include('lead_source' => nil, 'stage' => 'proposta_enviada', 'quote_request_status' => nil)
  end

  it 'shows the legacy opportunity with no quote request and no resend offered (CT-02, RF-56)' do
    body = read("pipeline_opportunities/#{opportunity.id}", admin)

    expect(body).to include('lead_source' => nil, 'quote_request' => nil, 'initial_template_failure' => nil,
                            'quote_request_resend_available' => false)
    expect(body['proposal']).to be_present
  end

  it 'keeps the approved and the legacy sent versions with their status, dates and artifact (RF-55, RNF-10)' do
    versions = read('proposals').sole['versions'].index_by { |version| version['id'] }

    expect(versions.fetch(approved_version.id)).to include('status' => 'approved', 'proposal_number' => nil)
    expect(Time.zone.parse(versions.fetch(approved_version.id)['approved_at'])).to eq(approved_at)
    expect(versions.fetch(sent_version.id)).to include('status' => 'sent', 'proposal_number' => nil, 'document_url' => nil)
    expect(read("proposals/#{proposal.id}")['versions'].pluck('status')).to contain_exactly('generated', 'approved', 'sent')
  end

  it 'keeps the legacy status codes and reads the new approval and delivery fields as empty (RF-26, CT-01)' do
    expect(ScanSolo::ProposalVersion.statuses.slice('generating', 'generated', 'approved', 'sent', 'failed'))
      .to eq('generating' => 0, 'generated' => 1, 'approved' => 2, 'sent' => 3, 'failed' => 4)
    expect(ScanSolo::ProposalVersion.where(id: [generated_version.id, approved_version.id, sent_version.id]).pluck(:status).sort)
      .to eq(%w[approved generated sent])

    body = read('proposals').sole
    versions = body['versions'].index_by { |version| version['id'] }

    expect(body['lead_email_present']).to be(false)
    expect(versions.fetch(generated_version.id)).to include('status' => 'generated', 'approved_at' => nil, 'approved_by' => nil)
    expect(versions.fetch(approved_version.id)['approved_by']).to eq('id' => admin.id, 'name' => admin.name)
    versions.each_value do |version|
      expect(version).to include('rejected_at' => nil, 'rejected_by' => nil, 'rejection_reason' => nil,
                                 'delivery' => { 'email_status' => nil, 'notice_status' => nil })
    end
    expect(read("pipeline_opportunities/#{opportunity.id}")).to include('lead_email' => nil)
  end

  it 'keeps the historical proposal.send request and callback untouched and readable (CT-06, CT-11)' do
    read("pipeline_opportunities/#{opportunity.id}")
    read('proposals')

    expect(ScanSolo::MakeRequest.find_by!(correlation_id: send_correlation_id)).to have_attributes(action: 'proposal.send', status: 'completed')
    expect(ScanSolo::MakeCallback.applied.find_by!(correlation_id: send_correlation_id).action).to eq('proposal.send')
    expect(sent_version.reload).to have_attributes(status: 'sent', approved_at: approved_at)
    expect(ScanSolo::AiAgentConfig.published_for(account).require_proposal_approval).to be(true)
  end
end
