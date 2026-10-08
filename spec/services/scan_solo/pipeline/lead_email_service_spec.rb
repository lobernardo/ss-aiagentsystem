# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Pipeline::LeadEmailService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :qualificado)
  end

  it 'writes the e-mail on the native contact (RF-09)' do
    described_class.call(opportunity: opportunity, email: 'lead@empresa.com.br')

    expect(contact.reload.email).to eq('lead@empresa.com.br')
    expect(opportunity).to be_lead_email_valid
  end

  it 'raises contact_conflict for an e-mail of another contact and keeps the contact unchanged (CT-09)' do
    contact.update!(email: 'antigo@empresa.com.br')
    create(:contact, account: account, email: 'lead@empresa.com.br')

    expect { described_class.call(opportunity: opportunity, email: 'Lead@Empresa.com.br') }
      .to raise_error(an_object_having_attributes(class: CustomExceptions::ScanSolo::LeadEmailRejected, code: 'contact_conflict'))

    expect(contact.email).to eq('antigo@empresa.com.br')
    expect(contact.reload.email).to eq('antigo@empresa.com.br')
  end

  it 'accepts an e-mail used by a contact of another account' do
    create(:contact, email: 'lead@empresa.com.br')

    described_class.call(opportunity: opportunity, email: 'lead@empresa.com.br')

    expect(contact.reload.email).to eq('lead@empresa.com.br')
  end
end
