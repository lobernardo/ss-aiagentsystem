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

  %i[approve? reject? retry?].each do |action|
    describe "##{action} (RF-04, RF-05, RF-15)" do
      it 'allows an administrator' do
        account_user.update!(role: :administrator)

        expect(policy.public_send(action)).to be true
      end

      it 'allows the agent published as commercial user' do
        ScanSolo::AiAgentConfig.draft_for!(account).update!(commercial_user_id: user.id)
        ScanSolo::AiAgent::PublishService.new(account: account).call

        expect(policy.public_send(action)).to be true
      end

      it 'denies another agent' do
        ScanSolo::AiAgentConfig.draft_for!(account).update!(commercial_user_id: create(:user, account: account).id)
        ScanSolo::AiAgent::PublishService.new(account: account).call

        expect(policy.public_send(action)).to be false
      end

      it 'denies an agent set as commercial user only in the unpublished draft' do
        ScanSolo::AiAgentConfig.draft_for!(account).update!(commercial_user_id: user.id)

        expect(policy.public_send(action)).to be false
      end
    end
  end

  it 'allows send for the owner or an administrator only' do
    expect(policy.send?).to be true
    allow(opportunity).to receive(:owner_id).and_return(nil)
    expect(policy.send?).to be false
    account_user.update!(role: :administrator)
    expect(policy.send?).to be true
  end
end
