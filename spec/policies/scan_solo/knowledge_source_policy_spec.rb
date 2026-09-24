require 'rails_helper'

RSpec.describe ScanSolo::KnowledgeSourcePolicy do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :agent) }
  let(:account_user) { account.account_users.find_by!(user: user) }
  let(:context) { { user: user, account: account, account_user: account_user } }
  let(:record) { nil }
  let(:policy) { described_class.new(context, record) }

  it 'allows account users to index' do
    expect(policy.index?).to be true
  end

  it 'allows account users to show' do
    expect(policy.show?).to be true
  end

  it 'reserves create for administrators' do
    expect(policy.create?).to be false
    account_user.update!(role: :administrator)
    expect(policy.create?).to be true
  end

  it 'reserves update for administrators' do
    expect(policy.update?).to be false
    account_user.update!(role: :administrator)
    expect(policy.update?).to be true
  end

  it 'reserves destroy for administrators' do
    expect(policy.destroy?).to be false
    account_user.update!(role: :administrator)
    expect(policy.destroy?).to be true
  end

  it 'reserves reindex for administrators' do
    expect(policy.reindex?).to be false
    account_user.update!(role: :administrator)
    expect(policy.reindex?).to be true
  end

  it 'reserves retrieval_tests for administrators' do
    expect(policy.retrieval_tests?).to be false
    account_user.update!(role: :administrator)
    expect(policy.retrieval_tests?).to be true
  end
end
