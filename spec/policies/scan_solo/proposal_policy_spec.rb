require 'rails_helper'

RSpec.describe ScanSolo::ProposalPolicy do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :agent) }
  let(:account_user) { account.account_users.find_by!(user: user) }
  let(:context) { { user: user, account: account, account_user: account_user } }
  let(:policy) { described_class.new(context, record) }

  let(:record) { instance_double(ScanSolo::Proposal, opportunity: opportunity) }
  let(:opportunity) { instance_double(ScanSolo::PipelineOpportunity, owner_id: user.id) }

  it 'allows account users to index' do
    expect(policy.index?).to be true
  end

  it 'allows account users to show' do
    expect(policy.show?).to be true
  end

  it 'allows account users to generate' do
    expect(policy.generate?).to be true
  end

  it 'reserves approve for administrators' do
    expect(policy.approve?).to be false
    account_user.update!(role: :administrator)
    expect(policy.approve?).to be true
  end

  it 'reserves retry for administrators' do
    expect(policy.retry?).to be false
    account_user.update!(role: :administrator)
    expect(policy.retry?).to be true
  end

  it 'allows send for the owner or an administrator only' do
    expect(policy.send?).to be true
    allow(opportunity).to receive(:owner_id).and_return(nil)
    expect(policy.send?).to be false
    account_user.update!(role: :administrator)
    expect(policy.send?).to be true
  end
end
