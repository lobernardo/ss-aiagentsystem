# RF-48 "request proposal generation" / "request proposal approval/send
# where allowed" -- RF-73 requires these three exposed as separable
# actions, never collapsed into one implicit step. The deterministic Make
# proposal integration (RF-73-RF-83) is a dedicated later phase (T57-T61);
# these handlers register the action ids/classification/schema now, and
# record a validated "requested" audit trail entry through T38's executor
# -- they do not invent a price/discount/total (RF-76 stays satisfied
# because no handler here writes a commercial value anywhere).
# `proposal_approve`/`proposal_send` are requires_confirmation, matching
# ScanSolo::AiTurn::InputGuardrail::CONFIRMATION_ONLY_ACTIONS.
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

  class Generate
    CLASSIFICATION = :automatic
    SCHEMA = ScanSolo::Actions::ProposalActions::BASE_SCHEMA

    def self.call(params:, **)
      opportunity = ScanSolo::PipelineOpportunity.find(params[:opportunity_id])

      { status: 'requested', action: 'proposal.generate', opportunity_id: opportunity.id }
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
      opportunity = ScanSolo::PipelineOpportunity.find(params[:opportunity_id])

      { status: 'requested', action: 'proposal.send', opportunity_id: opportunity.id }
    end
  end
end
# rubocop:enable Style/OneClassPerFile
