# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::AiTurn::ContextAssembler do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:contact) { create(:contact, account: account, name: 'Maria', email: 'maria@example.com') }
  let(:conversation) { create(:conversation, account: account, contact: contact) }

  let(:message) do
    create(:message, account: account, conversation: conversation, message_type: :incoming, sender: contact,
                     content: 'Qual o preco do plano?')
  end
  let(:config) do
    draft = ScanSolo::AiAgentConfig.draft_for!(account)
    draft.update!(required_qualification_fields: %w[budget area])
    draft
  end
  let(:no_attachments) { ScanSolo::AiTurn::AttachmentReader::Result.new(updates: [], evidence: [], urls: []) }

  describe '.call' do
    it 'references all five RF-39 sources, each either populated or explicitly not_applicable' do
      snapshot = described_class.call(message: message, config: config, attachment_reading: no_attachments, retrieval_service: mock_retrieval_service)

      expect(snapshot.keys).to include(:conversation_history, :contact_context, :pipeline_context,
                                       :proposal_context, :knowledge_context)

      expect(snapshot[:conversation_history]).to be_an(Array)
      expect(snapshot[:contact_context]).to include(available: true, name: 'Maria')
      expect(snapshot[:pipeline_context]).to eq(available: false, reason: 'not_applicable')
      expect(snapshot[:proposal_context]).to eq(available: false, reason: 'not_applicable')
      expect(snapshot[:knowledge_context]).to eq(chunks: [], failure_reason: nil)
    end

    it 'includes recent canonical conversation history from native Message records' do
      snapshot = described_class.call(message: message, config: config, attachment_reading: no_attachments, retrieval_service: mock_retrieval_service)

      expect(snapshot[:conversation_history].last).to include(role: 'customer', content: 'Qual o preco do plano?')
    end

    it 'keeps the most recent messages, oldest first, when the history exceeds the limit' do
      create(:message, account: account, conversation: conversation, message_type: :incoming, sender: contact, content: 'mais antiga',
                       created_at: 2.hours.ago)
      create_list(:message, described_class::RECENT_MESSAGE_LIMIT, account: account, conversation: conversation, message_type: :incoming,
                                                                   sender: contact, content: 'recente', created_at: 1.hour.ago)

      history = described_class.call(message: message, config: config, attachment_reading: no_attachments,
                                     retrieval_service: mock_retrieval_service)[:conversation_history]

      expect(history.size).to eq(described_class::RECENT_MESSAGE_LIMIT)
      expect(history.pluck(:content)).not_to include('mais antiga')
      expect(history.last[:content]).to eq('Qual o preco do plano?')
    end

    it 'includes pipeline context when an opportunity exists for the conversation' do
      ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation,
                                            stage: :em_qualificacao)

      snapshot = described_class.call(message: message, config: config, attachment_reading: no_attachments, retrieval_service: mock_retrieval_service)

      expect(snapshot[:pipeline_context]).to include(available: true, stage: 'em_qualificacao')
    end

    it 'lists the collected and missing required qualification fields of the opportunity (RF-05)' do
      opportunity = ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :em_qualificacao)
      ScanSolo::LeadState::Writer.new(lead_state: opportunity.lead_state)
                                 .apply_field!(key: 'area', value: '800 m²', status: 'confirmado', source_message_id: message.id)

      snapshot = described_class.call(message: message, config: config, attachment_reading: no_attachments, retrieval_service: mock_retrieval_service)

      expect(snapshot[:pipeline_context]).to include(collected_fields: { 'area' => '800 m²' }, missing_fields: ['budget'])
    end

    it 'treats native name and email only in the Contact as missing (RF-08)' do
      config.update!(required_qualification_fields: ['Nome', 'E-mail', 'Cidade / UF'])
      opportunity = ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :em_qualificacao)
      ScanSolo::LeadState::Writer.new(lead_state: opportunity.lead_state)
                                 .apply_field!(key: 'cidade_uf', value: 'Rio/RJ', status: 'confirmado', source_message_id: message.id)

      snapshot = described_class.call(message: message, config: config, attachment_reading: no_attachments, retrieval_service: mock_retrieval_service)

      expect(snapshot[:pipeline_context]).to include(collected_fields: { 'Cidade / UF' => 'Rio/RJ' }, missing_fields: %w[Nome E-mail])
    end

    it 'shows a nao_informado required field as collected with the neutral text (proposta-template-local RF-33 a)' do
      config.update!(required_qualification_fields: ['Empresa', 'Profundidade de investigação'])
      opportunity = ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :em_qualificacao)
      writer = ScanSolo::LeadState::Writer.new(lead_state: opportunity.lead_state)
      writer.apply_field!(key: 'empresa', value: 'ACME', status: 'confirmado', source_message_id: message.id)
      writer.apply_field!(key: 'profundidade', value: 'não sei', status: 'nao_informado', source_message_id: message.id)

      snapshot = described_class.call(message: message, config: config, attachment_reading: no_attachments, retrieval_service: mock_retrieval_service)

      expect(snapshot[:pipeline_context]).to include(
        collected_fields: { 'Empresa' => 'ACME', 'Profundidade de investigação' => 'não informado pelo cliente' }, missing_fields: []
      )
    end

    describe 'lead state context (RF-09, RF-17, RF-20, RF-25)' do
      let(:opportunity) do
        ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :em_qualificacao)
      end
      let(:snapshot) do
        described_class.call(message: message, config: config, attachment_reading: no_attachments, retrieval_service: mock_retrieval_service)
      end

      it 'is not applicable without an opportunity' do
        expect(snapshot[:lead_state_context]).to eq(available: false, reason: 'not_applicable')
      end

      it 'carries the projection with the eligible keys, required first' do
        opportunity

        expect(snapshot[:lead_state_context]).to include(intent: nil, qualification: { status: 'em_andamento', completed_at: nil })
        expect(snapshot[:lead_state_context][:eligible_keys].first(3)).to eq(%w[area empresa cargo])
        expect(snapshot[:lead_state_context][:status]).to include(stage: 'em_qualificacao', missing_fields: %w[budget area])
      end

      it 'overlays the extractions of the current message and exposes their evidence' do
        opportunity
        attachment = message.attachments.create!(account_id: account.id, file_type: :location, coordinates_lat: -22.9, coordinates_long: -43.2)
        reading = ScanSolo::AiTurn::AttachmentReader.call(message: message.reload)

        context = described_class.call(message: message, config: config, attachment_reading: reading,
                                       retrieval_service: mock_retrieval_service)[:lead_state_context]

        expect(context[:eligible_keys]).not_to include('link_local')
        expect(context[:attachment_extraction]).to eq(
          [{ attachment_id: attachment.id, file_type: 'location', file_name: nil, extracted: true, reason: nil }]
        )
      end

      it 'does not allow a summary without any event' do
        opportunity

        expect(snapshot[:lead_state_context][:summary_allowed]).to be(false)
      end

      it 'allows a summary after a stage change that follows the last AI reply' do
        create(:message, account: account, conversation: conversation, message_type: :outgoing, content: 'resposta',
                         additional_attributes: { 'scansolo_origin' => 'ai' }, created_at: 1.hour.ago)
        ScanSolo::Pipeline::StageTransitionService.new(opportunity: opportunity, target_stage: 'qualificado').call

        expect(snapshot[:lead_state_context][:summary_allowed]).to be(true)
      end

      it 'does not allow a summary when the stage change precedes the last AI reply' do
        ScanSolo::Pipeline::StageTransitionService.new(opportunity: opportunity, target_stage: 'qualificado').call
        create(:message, account: account, conversation: conversation, message_type: :outgoing, content: 'resposta',
                         additional_attributes: { 'scansolo_origin' => 'ai' }, created_at: 1.hour.from_now)

        expect(snapshot[:lead_state_context][:summary_allowed]).to be(false)
      end
    end

    describe 'collection rounds (proposta-template-local RF-34, RF-35, RF-36)' do
      let(:opportunity) do
        ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :em_qualificacao)
      end
      let(:writer) { ScanSolo::LeadState::Writer.new(lead_state: opportunity.lead_state) }
      let(:create_turn) do
        lambda do |status: :succeeded, snapshot: {}, sent: true|
          trigger = create(:message, account: account, conversation: conversation, message_type: :incoming, sender: contact, created_at: 1.hour.ago)
          reply = create(:message, account: account, conversation: conversation, message_type: :outgoing, created_at: 1.hour.ago) if sent
          ScanSolo::AiTurn.create!(message: trigger, conversation: conversation, correlation_id: SecureRandom.uuid, invocation_status: status,
                                   response_message_id: reply&.id, context_snapshot: snapshot)
        end
      end
      let(:snapshot) do
        described_class.call(message: message, config: config, attachment_reading: no_attachments, retrieval_service: mock_retrieval_service)
      end

      before do
        writer.set_intent!(intent: 'orcamento', source_message_id: message.id)
      end

      it 'counts only the sent turns whose reply asked a field' do
        create_turn.call(snapshot: { 'asked_fields' => ['area'] })
        create_turn.call(snapshot: { 'asked_fields' => [] })
        create_turn.call(snapshot: { 'asked_fields' => ['profundidade'] })

        expect(snapshot[:lead_state_context][:collection_rounds]).to eq(2)
      end

      it 'does not count suppressed, failed or unsent turns, turns without the key or turns before the lead state' do
        create_turn.call(status: :suppressed, snapshot: { 'asked_fields' => ['area'] })
        create_turn.call(status: :failed, snapshot: { 'asked_fields' => ['area'] })
        create_turn.call(sent: false, snapshot: { 'asked_fields' => ['area'] })
        create_turn.call(snapshot: {})
        create_turn.call(snapshot: { 'asked_fields' => ['area'] }).update!(created_at: opportunity.lead_state.created_at - 1.minute)

        expect(snapshot[:lead_state_context][:collection_rounds]).to eq(0)
      end

      it 'flags the initial explanation only with 0 rounds' do
        expect(snapshot[:lead_state_context]).to include(collection_rounds: 0, collection_intro: true, collection_offer_instructed: false)
        expect(snapshot[:collection_offer_instructed]).to be(false)
      end

      it 'flags the bulk offer at the top level with 2 rounds and no recorded offer' do
        2.times { create_turn.call(snapshot: { 'asked_fields' => ['area'] }) }

        expect(snapshot[:lead_state_context]).to include(collection_rounds: 2, collection_intro: false, collection_offer_instructed: true)
        expect(snapshot[:collection_offer_instructed]).to be(true)
      end

      it 'does not flag the bulk offer once it was recorded' do
        2.times { create_turn.call(snapshot: { 'asked_fields' => ['area'] }) }
        writer.record_collection_offer!(at: Time.current, source_message_id: message.id)

        expect(snapshot[:collection_offer_instructed]).to be(false)
      end

      it 'flags neither instruction for a non-budget intent or a concluded qualification' do
        2.times { create_turn.call(snapshot: { 'asked_fields' => ['area'] }) }
        writer.set_intent!(intent: 'duvida', source_message_id: message.id)

        expect(snapshot[:lead_state_context]).to include(collection_intro: false, collection_offer_instructed: false)

        writer.set_intent!(intent: 'orcamento', source_message_id: message.id)
        writer.complete!(at: Time.current)
        context = described_class.call(message: message, config: config, attachment_reading: no_attachments,
                                       retrieval_service: mock_retrieval_service)
        expect(context[:lead_state_context]).to include(collection_intro: false, collection_offer_instructed: false)
      end

      it 'is false at the top level without an opportunity' do
        conversation_without_opportunity = create(:conversation, account: account, contact: contact)
        other = create(:message, account: account, conversation: conversation_without_opportunity, message_type: :incoming, sender: contact)

        context = described_class.call(message: other, config: config, attachment_reading: no_attachments, retrieval_service: mock_retrieval_service)

        expect(context[:collection_offer_instructed]).to be(false)
      end
    end

    describe 'history with attachments (RF-16)' do
      it 'describes a location-only message with its coordinates and link' do
        location_message = create(:message, account: account, conversation: conversation, message_type: :incoming, sender: contact, content: nil)
        attachment = location_message.attachments.create!(account_id: account.id, file_type: :location, coordinates_lat: -22.9,
                                                          coordinates_long: -43.2)
        reading = ScanSolo::AiTurn::AttachmentReader.call(message: location_message.reload)

        snapshot = described_class.call(message: location_message, config: config, attachment_reading: reading,
                                        retrieval_service: mock_retrieval_service)

        expect(snapshot[:conversation_history].last).to include(
          content: nil, urls: [],
          attachments: [{ id: attachment.id, type: 'location', file_name: nil, lat: -22.9, long: -43.2,
                          link: 'https://www.google.com/maps?q=-22.9,-43.2', extracted: true }]
        )
      end

      it 'describes a PDF-only message with its type and file name' do
        pdf_message = create(:message, account: account, conversation: conversation, message_type: :incoming, sender: contact, content: nil)
        attachment = attach_pdf(pdf_message, 'lead_state_scanned.pdf')
        reading = ScanSolo::AiTurn::AttachmentReader.call(message: pdf_message.reload)

        snapshot = described_class.call(message: pdf_message, config: config, attachment_reading: reading,
                                        retrieval_service: mock_retrieval_service)

        expect(snapshot[:conversation_history].last[:attachments]).to eq(
          [{ id: attachment.id, type: 'pdf', file_name: 'lead_state_scanned.pdf', lat: nil, long: nil, link: nil, extracted: false }]
        )
      end

      it 'lists the URLs of a message' do
        link_message = create(:message, account: account, conversation: conversation, message_type: :incoming, sender: contact,
                                        content: 'segue o edital https://exemplo.com.br/edital.')

        snapshot = described_class.call(message: link_message, config: config, attachment_reading: no_attachments,
                                        retrieval_service: mock_retrieval_service)

        expect(snapshot[:conversation_history].last).to include(attachments: [], urls: ['https://exemplo.com.br/edital'])
      end

      it 'marks an earlier attachment as extracted when the lead state records it as origin' do
        opportunity = ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :em_qualificacao)
        earlier = create(:message, account: account, conversation: conversation, message_type: :incoming, sender: contact, content: nil,
                                   created_at: 1.hour.ago)
        attachment = earlier.attachments.create!(account_id: account.id, file_type: :location, coordinates_lat: 1, coordinates_long: 2)
        ScanSolo::LeadState::Writer.new(lead_state: opportunity.lead_state)
                                   .apply_field!(key: 'link_local', value: 'https://www.google.com/maps?q=1.0,2.0', status: 'inferido',
                                                 source_message_id: earlier.id, source_attachment_id: attachment.id)

        snapshot = described_class.call(message: message, config: config, attachment_reading: no_attachments,
                                        retrieval_service: mock_retrieval_service)

        entry = snapshot[:conversation_history].find { |history| history[:attachments].present? }
        expect(entry[:attachments].sole).to include(id: attachment.id, extracted: true)
      end

      it 'runs the same number of queries with 1 and 5 attachments' do
        ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :em_qualificacao)
        config

        counts = [1, 5].map do |size|
          current = create(:message, account: account, conversation: conversation, message_type: :incoming, sender: contact, content: nil)
          size.times { attach_pdf(current, 'lead_state_scanned.pdf') }
          current.reload
          reading = ScanSolo::AiTurn::AttachmentReader::Result.new(updates: [], evidence: [], urls: [])
          count_queries do
            described_class.call(message: current, config: config, attachment_reading: reading, retrieval_service: mock_retrieval_service)
          end
        end

        expect(counts.first).to eq(counts.last)
      end
    end

    describe 'RF-46: knowledge evidence' do
      it 'returns the retrieved chunks with source title, chunk id and similarity score' do
        result = ScanSolo::Knowledge::RetrievalService::Result.new(chunk_id: 7, source_id: 3, source_title: 'Planos', source_type: 'faq',
                                                                   content_snippet: 'O plano custa...', similarity_score: 0.91)
        retrieval = Struct.new(:noop) { define_singleton_method(:call) { |**| { results: [result], failure_reason: nil } } }

        snapshot = described_class.call(message: message, config: config, attachment_reading: no_attachments, retrieval_service: retrieval)

        expect(snapshot[:knowledge_context]).to eq(
          chunks: [{ source_id: 3, source_title: 'Planos', chunk_id: 7, similarity_score: 0.91, content: 'O plano custa...' }],
          failure_reason: nil
        )
      end

      it 'keeps no chunks and the failure reason on a retrieval outage' do
        outage = Struct.new(:noop) { def self.call(**) = { results: [], failure_reason: 'PG::ConnectionBad: down' } }

        snapshot = described_class.call(message: message, config: config, attachment_reading: no_attachments, retrieval_service: outage)

        expect(snapshot[:knowledge_context]).to eq(chunks: [], failure_reason: 'PG::ConnectionBad: down')
      end

      it 'skips retrieval for an attachment-only message' do
        attachment_only = create(:message, account: account, conversation: conversation, message_type: :incoming, sender: contact, content: nil)
        retrieval = class_double(ScanSolo::Knowledge::RetrievalService)
        allow(retrieval).to receive(:call)

        snapshot = described_class.call(message: attachment_only, config: config, attachment_reading: no_attachments, retrieval_service: retrieval)

        expect(retrieval).not_to have_received(:call)
        expect(snapshot[:knowledge_context]).to eq(chunks: [], failure_reason: nil)
      end
    end

    describe 'RF-40: durable memory is auxiliary and subordinate to canonical history' do
      it 'defaults to disabled without removing conversation_history' do
        snapshot = described_class.call(message: message, config: config, attachment_reading: no_attachments,
                                        retrieval_service: mock_retrieval_service)

        expect(snapshot[:durable_memory]).to eq(enabled: false)
        expect(snapshot[:conversation_history]).not_to be_empty
      end

      it 'is included as an auxiliary layer when a memory_provider is configured' do
        snapshot = described_class.call(
          message: message,
          config: config,
          attachment_reading: no_attachments,
          retrieval_service: mock_retrieval_service,
          memory_provider: ->(**) { [{ fact: 'cliente prefere WhatsApp' }] }
        )

        expect(snapshot[:durable_memory][:enabled]).to be true
        expect(snapshot[:durable_memory][:entries]).not_to be_empty
        expect(snapshot[:conversation_history]).not_to be_empty
      end
    end
  end

  def attach_pdf(target, name)
    attachment = target.attachments.new(account_id: account.id, file_type: :file)
    attachment.file.attach(io: Rails.root.join("spec/fixtures/files/scansolo/#{name}").open, filename: name, content_type: 'application/pdf')
    attachment.save!
    attachment
  end

  def count_queries(&)
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name].in?(%w[SCHEMA TRANSACTION]) || payload[:cached] }
    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record', &)
    count
  end

  def mock_retrieval_service
    Struct.new(:noop) { def self.call(**) = { results: [], failure_reason: nil } }
  end
end
