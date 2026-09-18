# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::ApplicationPolicy do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, :administrator, account: account) }
  let(:record) { account }

  let(:administrator_context) { { user: administrator, account: account, account_user: account.account_users.first } }
  let(:ambiguous_context) { { user: nil, account: nil, account_user: nil } }

  permissions :index?, :show?, :create?, :new?, :update?, :edit?, :destroy? do
    it 'denies an authenticated administrator by default (fail-closed)' do
      expect(described_class).not_to permit(administrator_context, record)
    end

    it 'denies an ambiguous/unauthorized user context by default' do
      expect(described_class).not_to permit(ambiguous_context, record)
    end
  end

  describe described_class::Scope do
    it 'resolves to no records by default, regardless of context' do
      scope = described_class.new(administrator_context, Account.all).resolve

      expect(scope).to eq(Account.none)
    end

    it 'resolves to no records for an ambiguous context' do
      scope = described_class.new(ambiguous_context, Account.all).resolve

      expect(scope).to eq(Account.none)
    end
  end
end
