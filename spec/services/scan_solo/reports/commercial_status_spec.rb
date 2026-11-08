# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Reports::CommercialStatus do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :qualificado)
  end
  let(:sent_at) { Time.zone.parse('2026-11-05T13:00:00Z') }
  let(:quote_request) do
    ScanSolo::QuoteRequest.create!(account: account, opportunity: opportunity, correlation_id: SecureRandom.uuid,
                                   status: :awaiting_reply, sent_at: sent_at)
  end
  let(:proposal) { ScanSolo::Proposal.create!(opportunity: opportunity) }

  def version_with(status)
    proposal.versions.create!(status: status, quote_request: quote_request)
  end

  def classify(quote_request:, current_version: nil)
    described_class.call(quote_request: quote_request, current_version: current_version)
  end

  describe '.call (RF-01 table, first true row wins)' do
    it 'row 1: without a quote request is nao_encaminhado' do
      expect(classify(quote_request: nil, current_version: nil)).to eq('nao_encaminhado')
    end

    it 'row 2: a handled_manually request is proposta_enviada_manual, whatever the version' do
      quote_request.update!(status: :handled_manually)

      expect(classify(quote_request: quote_request, current_version: version_with(:awaiting_approval))).to eq('proposta_enviada_manual')
    end

    it 'row 3: a sent current version is proposta_enviada' do
      quote_request.update!(status: :replied)

      expect(classify(quote_request: quote_request, current_version: version_with(:sent))).to eq('proposta_enviada')
    end

    it 'row 4: an awaiting_approval current version is proposta_em_aprovacao' do
      quote_request.update!(status: :replied)

      expect(classify(quote_request: quote_request, current_version: version_with(:awaiting_approval))).to eq('proposta_em_aprovacao')
    end

    it 'row 5: an awaiting_reply or correction_requested request is aguardando_artur' do
      expect(classify(quote_request: quote_request)).to eq('aguardando_artur')

      quote_request.update!(status: :correction_requested)
      expect(classify(quote_request: quote_request)).to eq('aguardando_artur')
    end

    it 'row 6: a replied request is resposta_recebida' do
      quote_request.update!(status: :replied)

      expect(classify(quote_request: quote_request)).to eq('resposta_recebida')
    end

    it 'keeps resposta_recebida for a replied request whose current version is generating, approved or failed' do
      quote_request.update!(status: :replied)

      %i[generating approved failed].each do |status|
        version = proposal.versions.create!(status: status)

        expect(classify(quote_request: quote_request, current_version: version)).to eq('resposta_recebida')
      end
    end

    it 'keeps aguardando_artur for an awaiting_reply request whose current version was rejected' do
      expect(classify(quote_request: quote_request, current_version: version_with(:rejected))).to eq('aguardando_artur')
    end

    it 'only ever returns one of the 6 VALUES and never escalado_wa' do
      expect(described_class::VALUES).to eq(
        %w[nao_encaminhado aguardando_artur resposta_recebida proposta_em_aprovacao proposta_enviada proposta_enviada_manual]
      )
      expect(described_class::VALUES).not_to include('escalado_wa')
    end
  end

  describe '.forwarded_at (RF-02)' do
    it 'returns the request sent_at' do
      expect(described_class.forwarded_at(quote_request)).to eq(sent_at)
    end

    it 'returns nil without a request or without sent_at' do
      quote_request.update!(sent_at: nil)

      expect(described_class.forwarded_at(nil)).to be_nil
      expect(described_class.forwarded_at(quote_request)).to be_nil
    end
  end

  it 'never writes to the database (RNF-03)' do
    quote_request.update!(status: :replied)
    version = version_with(:sent)
    writes = []
    callback = lambda do |*, payload|
      writes << payload[:sql] if payload[:sql].match?(/\A\s*(INSERT|UPDATE|DELETE)/i)
    end

    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
      classify(quote_request: nil)
      classify(quote_request: quote_request, current_version: version)
      classify(quote_request: quote_request)
      described_class.forwarded_at(quote_request)
    end

    expect(writes).to be_empty
  end
end
