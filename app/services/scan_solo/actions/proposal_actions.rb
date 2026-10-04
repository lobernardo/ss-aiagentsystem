# RF-48 "request proposal generation" / "request proposal approval/send
# where allowed" -- RF-73 requires these three exposed as separable
# actions, never collapsed into one implicit step. `proposal_generate` asks
# ScanSolo::Proposal::GenerateService for a new version through the
# configured provider (ScanSolo::Proposal::Integration, never the mock in
# production); approve/send only record a validated "requested" audit trail
# entry through the executor. No handler here writes a commercial value --
# only the provider callback does (RF-76).
# `proposal_approve`/`proposal_send` are requires_confirmation, matching
# ScanSolo::AiTurn::InputGuardrail::CONFIRMATION_ONLY_ACTIONS.
# RF-25: `proposal_generate` is no longer offered to the model (generation
# follows the validated commercial reply); the handler stays registered for
# the historical audit trail and only generates from that reply.
# rubocop:disable Style/OneClassPerFile -- RF-73 keeps the three separable
# proposal actions colocated, per the plan's single proposal_actions.rb file.
module ScanSolo::Actions::ProposalActions
  BASE_SCHEMA = {
    'type' => 'object',
    'properties' => {
      'opportunity_id' => { 'type' => 'integer' }
    },
    'required' => ['opportunity_id'],
    'additionalProperties' => false
  }.freeze

  # The ProposalVersion is created inside the caller's transaction (the AI
  # turn), while the provider request -- the Make HTTP call -- only runs once
  # every open transaction has committed, so a rolled-back turn never leaves
  # an orphan external request.
  class Generate
    CLASSIFICATION = :automatic
    SCHEMA = ScanSolo::Actions::ProposalActions::BASE_SCHEMA

    AfterCommitProvider = Struct.new(:provider) do
      def request_generation(**)
        ActiveRecord.after_all_transactions_commit { provider.request_generation(**) }
      end
    end

    def self.call(params:, **)
      provider = AfterCommitProvider.new(ScanSolo::Proposal::Integration.provider!)
      opportunity = ScanSolo::PipelineOpportunity.find(params[:opportunity_id])
      version = ScanSolo::Proposal::GenerateService.call(
        opportunity: opportunity, quote_request: opportunity.quote_request, correlation_id: SecureRandom.uuid, provider: provider
      )

      { status: 'requested', action: 'proposal.generate', opportunity_id: opportunity.id, proposal_version_id: version.id }
    end
  end

  class Approve
    CLASSIFICATION = :requires_confirmation
    SCHEMA = ScanSolo::Actions::ProposalActions::BASE_SCHEMA

    def self.call(params:, **)
      opportunity = ScanSolo::PipelineOpportunity.find(params[:opportunity_id])

      { status: 'requested', action: 'proposal.approve', opportunity_id: opportunity.id }
    end
  end

  class Send
    CLASSIFICATION = :requires_confirmation
    SCHEMA = ScanSolo::Actions::ProposalActions::BASE_SCHEMA

    def self.call(params:, **)
      ScanSolo::Proposal::Integration.provider!
      opportunity = ScanSolo::PipelineOpportunity.find(params[:opportunity_id])

      { status: 'requested', action: 'proposal.send', opportunity_id: opportunity.id }
    end
  end
end
# rubocop:enable Style/OneClassPerFile
