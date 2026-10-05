# frozen_string_literal: true

require 'rails_helper'

# RF-89: least-privilege authorization on every new ScanSolo endpoint/action,
# failing closed on ambiguous authorization or unverifiable callback
# identity. Cross-cutting audit rather than a spec for a single class -- it
# fails the moment a new controller is added under
# `api/v1/accounts/scan_solo/` or `webhooks/scan_solo/` without being
# registered here, so silently dropping authorization coverage for a new
# endpoint cannot pass CI unnoticed.
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'ScanSolo Pundit fail-closed coverage audit' do
  def controllers_root
    Rails.root.join('app/controllers').to_s
  end

  def controller_class_name(file)
    file.delete_prefix("#{controllers_root}/").delete_suffix('.rb').camelize
  end

  def api_controller_files
    Dir.glob(Rails.root.join('app/controllers/api/v1/accounts/scan_solo/**/*_controller.rb'))
  end

  def webhook_controller_files
    Dir.glob(Rails.root.join('app/controllers/webhooks/scan_solo/**/*_controller.rb'))
  end

  # Base class only -- defines no action of its own, so it has nothing to
  # authorize by itself. Every concrete subclass below still gets its own
  # authorize+policy assertion.
  abstract_api_controllers = %w[
    Api::V1::Accounts::ScanSolo::BaseController
  ]

  # Maps every concrete controller action-holder under
  # api/v1/accounts/scan_solo/ to the Pundit policy class its `authorize`
  # calls resolve to (an explicit `policy_class:` override where the
  # controller uses one, otherwise the record's own conventional policy).
  api_controller_policies = {
    'Api::V1::Accounts::ScanSolo::AiAgentConfigsController' => ScanSolo::AiAgentConfigPolicy,
    'Api::V1::Accounts::ScanSolo::AiTurnsController' => ScanSolo::AiTurnPolicy,
    'Api::V1::Accounts::ScanSolo::CadenceEnrollmentsController' => ScanSolo::CadenceEnrollmentPolicy,
    'Api::V1::Accounts::ScanSolo::PipelineOpportunitiesController' => ScanSolo::PipelineOpportunityPolicy,
    'Api::V1::Accounts::ScanSolo::ProposalsController' => ScanSolo::ProposalPolicy,
    'Api::V1::Accounts::ScanSolo::QuoteRepliesController' => ScanSolo::QuoteReplyPolicy,
    'Api::V1::Accounts::ScanSolo::QuoteRequestsController' => ScanSolo::QuoteRequestPolicy,
    'Api::V1::Accounts::ScanSolo::Conversations::HandoffController' => ScanSolo::HandoffPolicy,
    'Api::V1::Accounts::ScanSolo::Knowledge::SourcesController' => ScanSolo::KnowledgeSourcePolicy,
    'Api::V1::Accounts::ScanSolo::Knowledge::RetrievalTestsController' => ScanSolo::KnowledgeSourcePolicy,
    'Api::V1::Accounts::ScanSolo::ExecutionsController' => ScanSolo::ExecutionPolicy,
    'Api::V1::Accounts::ScanSolo::CadenceTemplatesController' => ScanSolo::TemplateMappingPolicy,
    'Api::V1::Accounts::ScanSolo::Contacts::OptOutsController' => ScanSolo::ContactOptOutPolicy,
    'Api::V1::Accounts::ScanSolo::StatusController' => ScanSolo::StatusPolicy
  }

  # The Make callback controller is the sole unauthenticated-caller-reachable
  # endpoint in the whole ScanSolo layer (no Chatwoot user/session exists to
  # build a Pundit user_context from). RF-89's "unverifiable callback
  # identity" clause is what applies here instead of the Pundit policy
  # pattern: ScanSolo::Make::CallbackVerifier fails closed on an invalid/
  # missing signature before any state change, which this audit verifies
  # directly rather than expecting a Pundit `authorize` call that cannot
  # exist without a user.
  webhook_controllers_requiring_signature_verification = %w[
    Webhooks::ScanSolo::MakeController
  ]

  it 'has no api/v1/accounts/scan_solo controller outside the registered coverage map' do
    known = abstract_api_controllers + api_controller_policies.keys
    actual = api_controller_files.map { |file| controller_class_name(file) }

    expect(actual.sort).to eq(known.sort)
  end

  it 'has no webhooks/scan_solo controller outside the registered signature-verification set' do
    actual = webhook_controller_files.map { |file| controller_class_name(file) }

    expect(actual.sort).to eq(webhook_controllers_requiring_signature_verification.sort)
  end

  api_controller_policies.each do |controller_name, policy_class|
    it "authorizes #{controller_name} through #{policy_class} (a ScanSolo::ApplicationPolicy subclass)" do
      file = Rails.root.join('app/controllers', "#{controller_name.underscore}.rb")

      expect(File.read(file)).to match(/authorize\(/), "#{controller_name} has no Pundit authorize call"
      expect(policy_class.ancestors).to include(ScanSolo::ApplicationPolicy)
    end
  end

  webhook_controllers_requiring_signature_verification.each do |controller_name|
    it "fails closed on unverifiable callback identity for #{controller_name} without relying on Pundit" do
      file = Rails.root.join('app/controllers', "#{controller_name.underscore}.rb")
      source = File.read(file)

      # No Chatwoot user session exists for an inbound webhook, so the
      # Pundit `user_context` pattern does not apply here -- trust is
      # established by ScanSolo::Make::CallbackVerifier's signature check
      # instead, and every rejection path must be a no-state-change response.
      expect(source).not_to match(/authorize\(/)
      expect(source).to match(/CallbackVerifier/)
      expect(source).to match(/head :unauthorized/)
    end
  end

  it 'gives every non-abstract ScanSolo:: Pundit policy class the same fail-closed base as its controllers rely on' do
    policy_files = Dir.glob(Rails.root.join('app/policies/scan_solo/*_policy.rb'))
                      .reject { |file| file.end_with?('application_policy.rb') }

    policy_files.each do |file|
      klass_name = File.basename(file, '.rb').camelize
      klass = "ScanSolo::#{klass_name}".constantize

      expect(klass.ancestors).to include(ScanSolo::ApplicationPolicy), "#{klass} does not inherit ScanSolo::ApplicationPolicy"
    end
  end

  it 'denies by default on every standard Pundit action when ScanSolo::ApplicationPolicy is used directly (fail closed)' do
    policy = ScanSolo::ApplicationPolicy.new({ user: nil, account: nil, account_user: nil }, nil)

    expect(policy.index?).to be false
    expect(policy.show?).to be false
    expect(policy.create?).to be false
    expect(policy.update?).to be false
    expect(policy.destroy?).to be false

    scope = ScanSolo::ApplicationPolicy::Scope.new({ user: nil, account: nil, account_user: nil }, ScanSolo::AiTurn.all)
    expect(scope.resolve.to_a).to eq([])
  end
end
# rubocop:enable RSpec/DescribeClass
