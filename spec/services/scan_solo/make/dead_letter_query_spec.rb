# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Make::DeadLetterQuery do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:other_account) { create(:account, scansolo_enabled: true) }

  def make_request(account:, status:, retry_count:)
    ScanSolo::MakeRequest.create!(
      account: account, correlation_id: SecureRandom.uuid, idempotency_key: SecureRandom.uuid,
      action: 'proposal.generate', payload: {}, status: status, retry_count: retry_count
    )
  end

  describe 'RF-86: a repeatedly-failing outbound request is visible via this query' do
    it 'includes a request that has failed at least the dead-letter retry threshold' do
      dead_letter_request = make_request(account: account, status: :failed,
                                         retry_count: ScanSolo::MakeRequest::DEAD_LETTER_RETRY_THRESHOLD)

      expect(described_class.call(account: account)).to include(dead_letter_request)
    end

    it 'excludes a request that has failed fewer times than the threshold' do
      recent_failure = make_request(account: account, status: :failed,
                                    retry_count: ScanSolo::MakeRequest::DEAD_LETTER_RETRY_THRESHOLD - 1)

      expect(described_class.call(account: account)).not_to include(recent_failure)
    end

    it 'excludes a request that eventually succeeded regardless of retry_count' do
      recovered_request = make_request(account: account, status: :completed,
                                       retry_count: ScanSolo::MakeRequest::DEAD_LETTER_RETRY_THRESHOLD + 5)

      expect(described_class.call(account: account)).not_to include(recovered_request)
    end

    it 'scopes results to the given account only' do
      other_accounts_dead_letter = make_request(account: other_account, status: :failed,
                                                retry_count: ScanSolo::MakeRequest::DEAD_LETTER_RETRY_THRESHOLD)

      expect(described_class.call(account: account)).not_to include(other_accounts_dead_letter)
    end
  end
end
