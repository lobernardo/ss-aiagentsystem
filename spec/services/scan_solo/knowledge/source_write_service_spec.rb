# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Knowledge::SourceWriteService do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:attributes) { { source_type: 'faq', title: 'Garantia', content: 'Garantia de 12 meses.', origin: 'manual' } }

  it 'creates a source and records knowledge_source.created' do
    source = nil
    expect { source = described_class.create!(account: account, actor: admin, attributes: attributes) }
      .to change(ScanSolo::AuditEvent, :count).by(1)

    expect(source).to be_persisted
    expect(source.added_by).to eq(admin)
    expect(ScanSolo::AuditEvent.last).to have_attributes(event_type: 'knowledge_source.created', subject: source, actor: admin)
    expect(ScanSolo::AuditEvent.last.payload).to include('title' => 'Garantia')
  end

  it 'updates a source and records knowledge_source.updated with changed field names only' do
    source = described_class.create!(account: account, actor: admin, attributes: attributes)

    described_class.update!(source: source, actor: admin, attributes: { content: 'Garantia de 24 meses.' })

    event = ScanSolo::AuditEvent.last
    expect(event).to have_attributes(event_type: 'knowledge_source.updated', subject: source, actor: admin)
    expect(event.payload['changed_fields']).to eq(['content'])
    expect(event.payload.to_json).not_to include('24 meses')
  end

  it 'destroys a source and records knowledge_source.deleted' do
    source = described_class.create!(account: account, actor: admin, attributes: attributes)

    expect { described_class.destroy!(source: source, actor: admin) }.to change(ScanSolo::KnowledgeSource, :count).by(-1)

    event = ScanSolo::AuditEvent.last
    expect(event).to have_attributes(event_type: 'knowledge_source.deleted', subject_id: source.id, subject_type: 'ScanSolo::KnowledgeSource')
  end

  it 'records no audit event when the source is invalid' do
    expect do
      described_class.create!(account: account, actor: admin, attributes: attributes.merge(origin: nil))
    end.to raise_error(ActiveRecord::RecordInvalid)

    expect(ScanSolo::AuditEvent.count).to eq(0)
  end
end
