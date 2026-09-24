require 'rails_helper'

RSpec.describe ScanSolo::TemplateMappingPolicy do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :agent) }
  let(:account_user) { account.account_users.find_by!(user: user) }
  let(:context) { { user: user, account: account, account_user: account_user } }
  let(:record) { nil }
  let(:policy) { described_class.new(context, record) }

  it 'allows account users to index' do
    expect(policy.index?).to be true
  end

  it 'reserves update for administrators' do
    expect(policy.update?).to be false
    account_user.update!(role: :administrator)
    expect(policy.update?).to be true
  end
end
