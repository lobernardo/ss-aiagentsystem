# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Make::CallbackApplicationService do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :qualificado)
  end
  let(:proposal) { ScanSolo::Proposal.create!(opportunity: opportunity) }
  let(:correlation_id) { SecureRandom.uuid }
  let(:version) { proposal.versions.create!(generate_correlation_id: correlation_id) }
  let!(:make_request) do
    ScanSolo::MakeRequest.create!(account: account, correlation_id: correlation_id, idempotency_key: correlation_id,
                                  action: 'proposal.generate', payload: { proposal_version_id: version.id }, status: :sent)
  end
  let(:payload) do
    {
      'correlation_id' => correlation_id, 'idempotency_key' => correlation_id, 'action' => 'proposal.generate', 'status' => 'success',
      'result' => { 'proposal_version_id' => version.id, 'artifact_url' => 'https://make.example/p.pdf', 'total_value' => 2500.0,
                    'currency' => 'BRL', 'valid_until' => 1.week.from_now.iso8601 }
    }
  end

  def valid_result(body = payload)
    ScanSolo::Make::CallbackVerifier::Result.new(signature_valid: true, rejection_reason: nil, payload: body, make_request: make_request)
  end

  def rejected_result(reason)
    ScanSolo::Make::CallbackVerifier::Result.new(signature_valid: true, rejection_reason: reason, payload: payload, make_request: nil)
  end

  it 'records an applied callback, completes the request and applies the result to the version in one pass' do
    expect(described_class.call(result: valid_result)).to eq(:applied)

    expect(ScanSolo::MakeCallback.applied.where(correlation_id: correlation_id).count).to eq(1)
    expect(make_request.reload).to be_completed
    expect(version.reload).to have_attributes(status: 'generated', value: BigDecimal(2500), artifact_url: 'https://make.example/p.pdf')
  end

  it 'returns :duplicate and changes nothing when the correlation id was already applied' do
    described_class.call(result: valid_result)

    expect do
      expect(described_class.call(result: valid_result)).to eq(:duplicate)
    end.not_to change(ScanSolo::MakeCallback, :count)
  end

  it 'records a rejection with applied: false without reserving the correlation id' do
    expect(described_class.call(result: rejected_result('schema_invalid'))).to eq(:rejected)
    expect(ScanSolo::MakeCallback.find_by(correlation_id: correlation_id)).to have_attributes(applied: false, rejection_reason: 'schema_invalid')

    expect(described_class.call(result: valid_result)).to eq(:applied)
    expect(version.reload).to be_generated
  end

  it 'rolls back the callback row when applying to the version fails' do
    version.update!(generate_correlation_id: SecureRandom.uuid)

    expect { described_class.call(result: valid_result) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(ScanSolo::MakeCallback.count).to eq(0)
    expect(make_request.reload).to be_sent
  end

  it 'keeps a non-retryable Make error code as the failure reason' do
    failure = payload.merge('status' => 'failure',
                            'result' => { 'proposal_version_id' => version.id, 'error_code' => 'invalid_price_table',
                                          'error_message' => 'no price', 'retryable' => false })

    described_class.call(result: valid_result(failure))

    expect(version.reload).to have_attributes(status: 'failed', failure_reason: 'invalid_price_table')
    expect(make_request.reload).to be_failed
  end
end
