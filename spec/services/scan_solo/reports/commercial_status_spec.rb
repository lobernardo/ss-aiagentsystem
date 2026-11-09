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

  def classify(quote_request:, current_version: nil, escalated: false)
    described_class.call(quote_request: quote_request, current_version: current_version, escalated: escalated)
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

    it 'has the 7 VALUES, including escalado_wa (escalação comercial CT-04)' do
      expect(described_class::VALUES).to eq(
        %w[nao_encaminhado aguardando_artur resposta_recebida proposta_em_aprovacao proposta_enviada proposta_enviada_manual escalado_wa]
      )
    end

    it 'requires the escalation input' do
      expect { described_class.call(quote_request: nil, current_version: nil) }.to raise_error(ArgumentError, /escalated/)
    end
  end

  # Escalação comercial RF-17: escalado_wa sits below the 3 proposal states.
  describe '.call for an escalated opportunity' do
    it 'is escalado_wa without a request, with an open request and with an answered request' do
      expect(classify(quote_request: nil, escalated: true)).to eq('escalado_wa')
      expect(classify(quote_request: quote_request, escalated: true)).to eq('escalado_wa')

      quote_request.update!(status: :replied)
      expect(classify(quote_request: quote_request, escalated: true)).to eq('escalado_wa')
    end

    it 'keeps proposta_enviada_manual for a request handled manually' do
      quote_request.update!(status: :handled_manually)

      expect(classify(quote_request: quote_request, escalated: true)).to eq('proposta_enviada_manual')
    end

    it 'keeps proposta_enviada for a sent current version' do
      expect(classify(quote_request: quote_request, current_version: version_with(:sent), escalated: true)).to eq('proposta_enviada')
    end

    it 'keeps proposta_em_aprovacao for a current version awaiting approval' do
      expect(classify(quote_request: quote_request, current_version: version_with(:awaiting_approval), escalated: true))
        .to eq('proposta_em_aprovacao')
    end

    it 'never returns escalado_wa when not escalated' do
      quote_request.update!(status: :replied)

      expect([classify(quote_request: nil), classify(quote_request: quote_request)]).to eq(%w[nao_encaminhado resposta_recebida])
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
