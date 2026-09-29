# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Qualification::FieldResolver do
  let(:account) { create(:account) }
  let(:config_v2_labels) do
    ['Objetivo do serviço', 'Cidade / UF', 'Endereço da obra', 'Área ou extensão', 'Profundidade de interesse',
     'Prazo desejado', 'Integração de segurança', 'Empresa', 'E-mail']
  end
  let(:labels) { ['Nome', 'E-mail', 'Telefone', 'Cidade / UF'] }
  let(:config) { ScanSolo::AiAgentConfig.new(required_qualification_fields: labels) }
  let(:contact) { create(:contact, account: account, name: '', email: nil, phone_number: nil, custom_attributes: {}) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:opportunity) { ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation) }
  let!(:lead_state) { ScanSolo::LeadState.find_or_create_by!(opportunity: opportunity) }
  let(:writer) { ScanSolo::LeadState::Writer.new(lead_state: lead_state) }
  let(:resolver) { described_class.call(opportunity: opportunity.reload, config: config) }

  def field(label)
    resolver.fields.find { |candidate| candidate.label == label }
  end

  describe 'lead state RF-02: closed catalog' do
    let(:catalog) do
      [
        { key: 'nome', block: 'identificacao', label: 'Contato' },
        { key: 'empresa', block: 'identificacao', label: 'Empresa / razão social' },
        { key: 'cargo', block: 'identificacao', label: 'Cargo' },
        { key: 'cnpj', block: 'identificacao', label: 'CNPJ' },
        { key: 'telefone', block: 'identificacao', label: 'Telefone' },
        { key: 'email', block: 'identificacao', label: 'E-mail principal' },
        { key: 'emails_copia', block: 'identificacao', label: 'E-mails em cópia' },
        { key: 'tipo_servico', block: 'servico', label: 'Tipo de serviço' },
        { key: 'tipo_intervencao', block: 'servico', label: 'Objetivo' },
        { key: 'tecnologia', block: 'servico', label: 'Tecnologia' },
        { key: 'interferencias_buscadas', block: 'servico', label: 'Interferências buscadas' },
        { key: 'cliente_final', block: 'local', label: 'Cliente / local final' },
        { key: 'cidade_uf', block: 'local', label: 'Cidade / UF' },
        { key: 'endereco_obra', block: 'local', label: 'Endereço' },
        { key: 'bairro', block: 'local', label: 'Bairro' },
        { key: 'link_local', block: 'local', label: 'Link' },
        { key: 'area', block: 'escopo', label: 'Área' },
        { key: 'metragem', block: 'escopo', label: 'Metragem' },
        { key: 'quantidade_pontos', block: 'escopo', label: 'Quantidade de pontos' },
        { key: 'profundidade', block: 'escopo', label: 'Profundidade de investigação' },
        { key: 'profundidade_intervencao', block: 'escopo', label: 'Profundidade da intervenção' },
        { key: 'superficie', block: 'escopo', label: 'Superfície' },
        { key: 'observacoes_tecnicas', block: 'escopo', label: 'Observações técnicas' },
        { key: 'data_desejada', block: 'execucao', label: 'Data desejada' },
        { key: 'prazo_desejado', block: 'execucao', label: 'Prazo' },
        { key: 'diarias', block: 'execucao', label: 'Diárias' },
        { key: 'integracao_seguranca', block: 'execucao', label: 'Integração' },
        { key: 'tempo_integracao', block: 'execucao', label: 'Tempo de integração' },
        { key: 'restricoes_acesso', block: 'execucao', label: 'Restrições de acesso' },
        { key: 'documentacoes_necessarias', block: 'execucao', label: 'Documentações necessárias' },
        { key: 'prazo_proposta', block: 'comercial', label: 'Prazo para proposta' },
        { key: 'email_envio_proposta', block: 'comercial', label: 'E-mail para envio' },
        { key: 'emails_copia_proposta', block: 'comercial', label: 'Cópias' },
        { key: 'condicoes_especiais', block: 'comercial', label: 'Condições especiais' }
      ]
    end

    it 'matches all 34 RF-02 fields, blocks and labels in order' do
      expect(described_class::CATALOG).to eq(catalog)
      expect(described_class::CATALOG.size).to eq(34)
      expect(described_class::CATALOG_KEYS).to eq(catalog.pluck(:key))
      expect(described_class::BLOCKS).to eq(%w[identificacao servico local escopo execucao comercial])
    end

    it 'resolves every RF-02 label to its canonical key' do
      catalog.each do |entry|
        expect(described_class.canonical_key(entry[:label])).to eq(entry[:key])
      end
    end

    it 'keeps commercial fields distinct from execution and contact fields' do
      expect(described_class.canonical_key('Prazo para proposta')).to eq('prazo_proposta')
      expect(described_class.canonical_key('E-mail para envio')).to eq('email_envio_proposta')
      expect(described_class.canonical_key('Objetivo do serviço')).to eq('tipo_intervencao')
    end

    it 'never assigns one normalized spelling to different keys' do
      pairs = described_class::ALIASES.flat_map do |key, aliases|
        [key, *aliases].map { |spelling| [described_class.normalize(spelling), key] }
      end
      pairs.group_by(&:first).each_value do |entries|
        expect(entries.map(&:last).uniq.size).to eq(1)
      end
    end
  end

  describe 'lead state RF-08: satisfied if and only if confirmado' do
    it 'reads "Nome" from contact.name without satisfying it' do
      contact.update!(name: 'Leonardo')

      expect(field('Nome').to_h).to eq(label: 'Nome', canonical_key: 'nome', value: 'Leonardo', origin: 'native', status: 'faltante',
                                       classification: 'obrigatorio', satisfied: false)
    end

    it 'does not satisfy a native name that is inferido in the lead state' do
      contact.update!(name: 'Milena (WhatsApp)')
      writer.apply_field!(key: 'nome', value: 'Milena (WhatsApp)', status: 'inferido', source_message_id: nil)

      expect(field('Nome')).to have_attributes(value: 'Milena (WhatsApp)', status: 'inferido', satisfied: false)
      expect(resolver.missing_labels).to include('Nome')
    end

    it 'prefers and satisfies a confirmado lead state value over the native column' do
      contact.update!(name: 'Milena (WhatsApp)')
      writer.apply_field!(key: 'nome', value: 'Milena Souza', status: 'confirmado', source_message_id: 1)

      expect(field('Nome')).to have_attributes(value: 'Milena Souza', origin: 'lead_state', status: 'confirmado', satisfied: true)
      expect(resolver.collected).to eq('Nome' => 'Milena Souza')
    end

    it 'reads "E-mail" and "Telefone" from the native columns' do
      contact.update!(email: 'a@b.com', phone_number: '+5521999990000')

      expect(field('E-mail')).to have_attributes(value: 'a@b.com', origin: 'native', satisfied: false)
      expect(field('Telefone')).to have_attributes(value: '+5521999990000', origin: 'native', satisfied: false)
    end

    it 'falls back to custom_attributes when the native value is blank' do
      contact.update!(custom_attributes: { 'Nome' => 'Ana' })

      expect(field('Nome')).to have_attributes(value: 'Ana', origin: 'custom_attribute', satisfied: false)
    end

    it 'ignores a faltante lead state entry when reading the value' do
      contact.update!(custom_attributes: { 'cidade_uf' => 'Rio/RJ' })
      lead_state.update!(fields: { 'cidade_uf' => { 'value' => nil, 'status' => 'faltante' } })

      expect(field('Cidade / UF')).to have_attributes(value: 'Rio/RJ', origin: 'custom_attribute', status: 'faltante')
    end

    it 'reports an unsatisfied field with no value and no origin' do
      expect(field('Nome')).to have_attributes(value: nil, origin: nil, status: 'faltante', satisfied: false)
      expect(field('Cidade / UF')).not_to be_satisfied
      expect(resolver.missing_labels).to eq(labels)
      expect(resolver.collected).to eq({})
    end

    it 'keeps config order in fields, missing_labels and collected' do
      writer.apply_field!(key: 'nome', value: 'Leonardo', status: 'confirmado', source_message_id: 1)
      writer.apply_field!(key: 'cidade_uf', value: 'Rio/RJ', status: 'confirmado', source_message_id: 1)

      expect(resolver.fields.map(&:label)).to eq(labels)
      expect(resolver.required_canonical_keys).to eq(%w[nome email telefone cidade_uf])
      expect(resolver.missing_labels).to eq(%w[E-mail Telefone])
      expect(resolver.collected).to eq('Nome' => 'Leonardo', 'Cidade / UF' => 'Rio/RJ')
    end

    it 'fails loudly when the opportunity has no lead state' do
      lead_state.destroy!

      expect { described_class.call(opportunity: opportunity.reload, config: config) }.to raise_error(NoMethodError)
    end
  end

  describe '.contact_value' do
    it 'reads the native column first, then custom_attributes by precedence' do
      contact.update!(name: 'Leonardo', custom_attributes: { 'cidade' => 'Rio', 'cidade_uf' => 'Rio/RJ' })

      expect(described_class.contact_value(contact: contact, canonical_key: 'nome')).to eq('Leonardo')
      expect(described_class.contact_value(contact: contact, canonical_key: 'cidade_uf')).to eq('Rio/RJ')
      expect(described_class.contact_value(contact: contact, canonical_key: 'cnpj')).to be_nil
    end
  end

  describe 'RF-03: normalization' do
    it 'normalizes separator, case and whitespace variants of "Cidade / UF" to the same form' do
      forms = ['Cidade / UF', 'cidade_uf', ' CIDADE/UF ', 'cidade-uf', 'cidade uf'].map { |key| described_class.normalize(key) }

      expect(forms.uniq).to eq(['cidade_uf'])
    end

    it 'removes diacritics' do
      expect(described_class.normalize('Área ou extensão')).to eq(described_class.normalize('area_ou_extensao'))
    end
  end

  describe 'RF-04: canonical alias map' do
    described_class::ALIASES.each do |canonical, spellings|
      [*spellings, canonical].each do |spelling|
        it "resolves #{spelling.inspect} and its variants to #{canonical}" do
          variants = [spelling, spelling.upcase, " #{spelling.tr(' ', '_')} ", I18n.transliterate(spelling).tr(' ', '-')]

          expect(variants.map { |variant| described_class.canonical_key(variant) }.uniq).to eq([canonical])
        end
      end
    end

    it 'resolves "NOME", "nome completo" and "name" to nome' do
      expect(['NOME', 'nome completo', 'name'].map { |key| described_class.canonical_key(key) }).to all(eq('nome'))
    end

    context 'with config v2 labels and values stored under the Make canonical keys' do
      let(:labels) { config_v2_labels }

      let(:values) do
        {
          'tipo_intervencao' => 'sondagem', 'cidade_uf' => 'Rio/RJ', 'endereco_obra' => 'Rua A, 1', 'area' => '800 m²',
          'profundidade' => '10 m', 'prazo_desejado' => 'amanhã', 'integracao_seguranca' => 'sim',
          'empresa' => 'ACME', 'email' => 'x@acme.com'
        }
      end

      it 'reads every config v2 label from custom attributes' do
        contact.update!(custom_attributes: values)

        expect(resolver.fields.map(&:value)).to eq(values.values_at(*resolver.required_canonical_keys))
        expect(resolver.fields.map(&:origin).uniq).to eq(['custom_attribute'])
        expect(resolver.missing_labels).to eq(labels)
      end

      it 'satisfies every config v2 label confirmed in the lead state' do
        values.each { |key, value| writer.apply_field!(key: key, value: value, status: 'confirmado', source_message_id: 1) }

        expect(resolver.missing_labels).to be_empty
        expect(field('Área ou extensão').value).to eq('800 m²')
      end

      it 'reads a label from a custom attribute with different accent and case' do
        contact.update!(custom_attributes: { 'AREA OU EXTENSAO' => '500 m²', 'endereco' => 'Rua B' })

        expect(field('Área ou extensão')).to have_attributes(value: '500 m²', origin: 'custom_attribute')
        expect(field('Endereço da obra')).to have_attributes(value: 'Rua B', origin: 'custom_attribute')
      end
    end
  end

  describe 'RF-05: labels outside the alias map' do
    let(:labels) { %w[Orçamento budget] }

    it 'uses the normalized label as canonical key and reads a normalized custom attribute' do
      contact.update!(custom_attributes: { 'orcamento' => '50k' })

      expect(field('Orçamento')).to have_attributes(canonical_key: 'orcamento', value: '50k', origin: 'custom_attribute')
    end

    it 'is never satisfied outside the catalog (lead state RF-15 fail-closed)' do
      contact.update!(custom_attributes: { 'orcamento' => '50k', 'budget' => '10k' })

      expect(resolver.fields.map { |f| [f.status, f.satisfied?] }).to eq([['faltante', false], ['faltante', false]])
      expect(resolver.missing_labels).to eq(%w[Orçamento budget])
    end
  end

  describe 'RF-21: read precedence' do
    it 'prefers the exact canonical key over the config label' do
      contact.update!(custom_attributes: { 'Cidade / UF' => 'Niterói/RJ', 'cidade_uf' => 'Rio/RJ' })

      expect(field('Cidade / UF').value).to eq('Rio/RJ')
    end

    it 'prefers the exact config label over other aliases' do
      contact.update!(custom_attributes: { 'Cidade / UF' => 'Niterói/RJ', 'cidade' => 'Rio' })

      expect(field('Cidade / UF').value).to eq('Niterói/RJ')
    end

    it 'follows alias-table order, then lexicographic order' do
      contact.update!(custom_attributes: { 'CIDADE' => 'Rio', 'cidade / uf' => 'Niterói/RJ', 'Cidade-UF' => 'Macaé/RJ' })

      expect(field('Cidade / UF').value).to eq('Macaé/RJ')
    end

    it 'skips blank values when choosing the key' do
      contact.update!(custom_attributes: { 'cidade_uf' => '', 'cidade' => 'Rio' })

      expect(field('Cidade / UF').value).to eq('Rio')
    end
  end

  describe '#make_qualification' do
    let(:labels) { config_v2_labels }

    it 'sends only present canonical Make keys, including natives outside the config, and never nil' do
      contact.update!(name: 'Leonardo', phone_number: '+5521999990000',
                      custom_attributes: { 'Cidade / UF' => 'Rio/RJ', 'Empresa' => 'ACME', 'Integração de segurança' => 'sim',
                                           'Orçamento' => '50k', 'area' => '' })

      expect(resolver.make_qualification).to eq(
        'empresa' => 'ACME', 'cidade_uf' => 'Rio/RJ', 'nome' => 'Leonardo', 'telefone' => '+5521999990000'
      )
      expect(resolver.make_qualification.keys).to all(match(/\A[a-z0-9_]+\z/))
    end

    it 'prefers present lead state values, confirmado or inferido' do
      contact.update!(name: 'Milena (WhatsApp)', custom_attributes: { 'area' => '500 m²' })
      writer.apply_field!(key: 'nome', value: 'Milena Souza', status: 'confirmado', source_message_id: 1)
      writer.apply_field!(key: 'area', value: '800 m²', status: 'inferido', source_message_id: 1)

      expect(resolver.make_qualification).to eq('area' => '800 m²', 'nome' => 'Milena Souza')
    end
  end

  describe 'RF-08 proposal gate: #proposal_gate_missing_labels' do
    let(:labels) { ['Área'] }

    it 'accepts an inferido required field once qualification is concluida' do
      writer.apply_field!(key: 'area', value: '800 m²', status: 'inferido', source_message_id: nil)
      writer.complete!(at: Time.current)

      expect(resolver.proposal_gate_missing_labels).to eq([])
      expect(resolver.missing_labels).to eq(['Área'])
    end

    it 'blocks on a faltante required field once qualification is concluida' do
      writer.complete!(at: Time.current)

      expect(resolver.proposal_gate_missing_labels).to eq(['Área'])
    end

    it 'blocks on an inferido required field while qualification is em_andamento' do
      writer.apply_field!(key: 'area', value: '800 m²', status: 'inferido', source_message_id: nil)

      expect(resolver.proposal_gate_missing_labels).to eq(['Área'])
    end

    it 'passes a confirmado required field while qualification is em_andamento' do
      writer.apply_field!(key: 'area', value: '800 m²', status: 'confirmado', source_message_id: 1)

      expect(resolver.proposal_gate_missing_labels).to eq([])
    end

    context 'with a required label outside the catalog' do
      let(:labels) { ['budget'] }

      it 'blocks a concluida qualification' do
        contact.update!(custom_attributes: { 'budget' => '10k' })
        writer.complete!(at: Time.current)

        expect(resolver.proposal_gate_missing_labels).to eq(['budget'])
      end
    end
  end

  describe 'RF-06: determinism' do
    it 'resolves without LLM, HTTP or message reads, returning equal results on repeated calls' do
      contact.update!(name: 'Leonardo', custom_attributes: { 'cidade' => 'Rio' })
      writer.apply_field!(key: 'email', value: 'a@b.com', status: 'confirmado', source_message_id: 1)
      allow(ScanSolo::TestMode::MockLlmProvider).to receive(:call).and_raise('LLM called')
      allow(RubyLLM).to receive(:chat).and_raise('LLM called')
      allow(Net::HTTP).to receive(:start).and_raise('HTTP called')
      allow(Net::HTTP).to receive(:new).and_raise('HTTP called')
      queries = []
      callback = ->(*, payload) { queries << payload[:sql] }

      results = ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
        Array.new(2) do
          resolved = described_class.call(opportunity: opportunity.reload, config: config)
          [resolved.fields.map(&:to_h), resolved.make_qualification, resolved.proposal_gate_missing_labels]
        end
      end

      expect(results.first).to eq(results.last)
      expect(queries.grep(/messages/)).to be_empty
    end

    it 'references no enterprise or Captain code' do
      source = File.read(Rails.root.join('app/services/scan_solo/qualification/field_resolver.rb'))

      expect(source).not_to match(/enterprise|Captain:{2}/i)
    end
  end
end
