# RF-01, RF-01a, RNF-01, RNF-06: creates the opportunity's single lead state.
# Only the caller that actually inserts the row seeds it: every RF-02 catalog
# field starts `faltante`, and each one with a value on the Contact (native
# column or `custom_attributes`) is then written `inferido` through the
# Writer, so it gets its history event. An existing state is never touched.
#
# Created with the opportunity (no `backfilled_at`) the qualification is
# always `em_andamento`. The additive backfill passes `backfilled_at` and
# concludes the states of opportunities already at or past `qualificado`,
# with the null-intent default next action and no source message -- without
# any stage transition, stage event, audit event or Contact write.
class ScanSolo::LeadState::InitializeService
  BACKFILL_CONCLUDED_STAGES = %w[qualificado proposta_enviada negociacao ganho perdido].freeze

  EMPTY_FIELD = { 'value' => nil, 'status' => 'faltante', 'updated_at' => nil, 'source_message_id' => nil, 'source_attachment_id' => nil }.freeze

  def self.call(opportunity:, backfilled_at: nil)
    new(opportunity: opportunity, backfilled_at: backfilled_at).call
  end

  def initialize(opportunity:, backfilled_at:)
    @opportunity = opportunity
    @backfilled_at = backfilled_at
  end

  def call
    ActiveRecord::Base.transaction do
      lead_state = ScanSolo::LeadState.create_or_find_by!(opportunity_id: opportunity.id) do |record|
        record.fields = ScanSolo::Qualification::FieldResolver::CATALOG_KEYS.index_with { EMPTY_FIELD }
      end
      seed!(ScanSolo::LeadState::Writer.new(lead_state: lead_state)) if lead_state.previously_new_record?
      lead_state
    end
  end

  private

  attr_reader :opportunity, :backfilled_at

  def seed!(writer)
    ScanSolo::Qualification::FieldResolver::CATALOG_KEYS.each do |key|
      value = ScanSolo::Qualification::FieldResolver.contact_value(contact: opportunity.contact, canonical_key: key)
      writer.apply_field!(key: key, value: value, status: 'inferido', source_message_id: nil) if value.present?
    end
    return unless backfilled_at && BACKFILL_CONCLUDED_STAGES.include?(opportunity.stage)

    writer.complete!(at: backfilled_at)
    writer.record_next_action!(value: ScanSolo::LeadState::DEFAULT_NEXT_ACTION_BY_INTENT[nil], source_message_id: nil)
  end
end
