# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'ScanSolo Pipeline Opportunities API create (CT-01)', type: :request do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:owner) { create(:user, account: account, role: :agent) }
  let(:channel) { create(:channel_whatsapp, account: account, sync_templates: false) }
  let(:inbox) { channel.inbox }
  let(:path) { "/api/v1/accounts/#{account.id}/scan_solo/pipeline_opportunities" }
  let(:allowed_inbox_ids) { [inbox.id] }
  let(:valid_params) do
    { name: 'Ana Souza', phone_number: '+5511987654321', email: 'ana@example.com', company: 'Solar Ltda', owner_id: owner.id, inbox_id: inbox.id }
  end
  let(:counts) do
    -> { [Contact.count, Conversation.count, ScanSolo::PipelineOpportunity.count, Message.count] }
  end

  before do
    stub_request(:post, 'https://waba.360dialog.io/v1/configs/webhook')
    ScanSolo::CadenceDefinition.create!(stage: 'novo_lead', version: 1, offsets: [2, 24, 48, 96])
    ScanSolo::AiAgentConfig.draft_for!(account).update!(name: 'Agente', enabled: true, allowed_inbox_ids: allowed_inbox_ids)
    ScanSolo::AiAgent::PublishService.new(account: account).call
  end

  def post_lead(params)
    post path, params: params, headers: agent.create_new_auth_token, as: :json
  end

  def expect_rejection(params, code)
    counts_before = counts.call

    post_lead(params)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('error' => code)
    expect(counts.call).to eq(counts_before)
  end

  describe 'request boundary (RF-05)' do
    it 'rejects a missing name with missing_name' do
      expect_rejection(valid_params.merge(name: ' '), 'missing_name')
    end

    it 'rejects a missing phone with invalid_phone' do
      expect_rejection(valid_params.except(:phone_number), 'invalid_phone')
    end

    it 'rejects a phone outside E.164 with invalid_phone' do
      expect_rejection(valid_params.merge(phone_number: '11987654321'), 'invalid_phone')
    end

    it 'rejects a malformed e-mail with invalid_email' do
      expect_rejection(valid_params.merge(email: 'ana@'), 'invalid_email')
    end

    it 'rejects an owner outside the account with invalid_owner' do
      expect_rejection(valid_params.merge(owner_id: create(:user).id), 'invalid_owner')
    end

    it 'rejects an inbox that is not WhatsApp with invalid_inbox' do
      api_inbox = create(:inbox, account: account)
      ScanSolo::AiAgentConfig.draft_for!(account).update!(allowed_inbox_ids: [inbox.id, api_inbox.id])
      ScanSolo::AiAgent::PublishService.new(account: account).call

      expect_rejection(valid_params.merge(inbox_id: api_inbox.id), 'invalid_inbox')
    end

    it 'rejects a WhatsApp inbox outside the published allowlist with invalid_inbox' do
      other_inbox = create(:channel_whatsapp, account: account, sync_templates: false).inbox

      expect_rejection(valid_params.merge(inbox_id: other_inbox.id), 'invalid_inbox')
    end
  end

  describe 'service rules (RF-05, RF-09)' do
    it 'rejects an opted-out contact with contact_opted_out' do
      contact = create(:contact, account: account, phone_number: valid_params[:phone_number], email: nil)
      ScanSolo::ContactExtension.resolve_for(contact).update!(opted_out: true, opted_out_at: Time.current)

      expect_rejection(valid_params, 'contact_opted_out')
    end

    it 'rejects phone and e-mail of two different contacts with contact_conflict' do
      create(:contact, account: account, phone_number: valid_params[:phone_number], email: nil)
      create(:contact, account: account, phone_number: nil, email: valid_params[:email])

      expect_rejection(valid_params, 'contact_conflict')
    end

    it 'rejects a contact with a non-terminal opportunity with opportunity_exists and its id' do
      contact = create(:contact, account: account, phone_number: valid_params[:phone_number], email: nil)
      open_opportunity = ScanSolo::PipelineOpportunity.create!(
        account: account, contact: contact, conversation: create(:conversation, account: account, contact: contact), stage: :em_qualificacao
      )
      counts_before = counts.call

      post_lead(valid_params)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'opportunity_exists', 'opportunity_id' => open_opportunity.id)
      expect(counts.call).to eq(counts_before)
    end
  end

  describe 'success' do
    it 'returns 201 with the show representation of a manual novo_lead opportunity and contact_created' do
      post_lead(valid_params)

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      opportunity = ScanSolo::PipelineOpportunity.find(body['id'])
      expect(body).to include('lead_source' => 'manual', 'stage' => 'novo_lead', 'contact_created' => true, 'owner_id' => owner.id,
                              'contact_name' => 'Ana Souza', 'conversation_id' => opportunity.conversation_id)
      expect(body['lead_state'].keys).to eq(%w[intent qualification next_action authorized_actions blocks status history])
      expect(body).to include('quote_request' => nil, 'proposal' => nil)
      expect(opportunity.conversation.inbox).to eq(inbox)
    end

    it 'reports contact_created false when the phone already belongs to a contact' do
      contact = create(:contact, account: account, phone_number: valid_params[:phone_number], email: nil)

      expect { post_lead(valid_params) }.not_to change(Contact, :count)

      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to include('contact_created' => false, 'contact_id' => contact.id)
    end
  end

  describe 'inbox selection (UI-01)' do
    it 'uses the only allowlisted WhatsApp inbox when inbox_id is omitted' do
      post_lead(valid_params.except(:inbox_id))

      expect(response).to have_http_status(:created)
      expect(ScanSolo::PipelineOpportunity.find(response.parsed_body['id']).conversation.inbox).to eq(inbox)
    end

    context 'with two allowlisted WhatsApp inboxes' do
      let(:second_inbox) { create(:channel_whatsapp, account: account, sync_templates: false).inbox }
      let(:allowed_inbox_ids) { [inbox.id, second_inbox.id] }

      it 'rejects an omitted inbox_id with invalid_inbox' do
        expect_rejection(valid_params.except(:inbox_id), 'invalid_inbox')
      end

      it 'accepts the chosen inbox' do
        post_lead(valid_params.merge(inbox_id: second_inbox.id))

        expect(response).to have_http_status(:created)
        expect(ScanSolo::PipelineOpportunity.find(response.parsed_body['id']).conversation.inbox).to eq(second_inbox)
      end
    end
  end

  it 'returns 404 when ScanSolo is disabled for the account' do
    account.update!(scansolo_enabled: false)
    counts_before = counts.call

    post_lead(valid_params)

    expect(response).to have_http_status(:not_found)
    expect(counts.call).to eq(counts_before)
  end
end
