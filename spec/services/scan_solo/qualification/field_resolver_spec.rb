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
  let(:resolver) { described_class.call(contact: contact, config: config) }

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

  describe 'RF-01/RF-02: native contact fields' do
    it 'satisfies "Nome" from contact.name with origin native' do
      contact.update!(name: 'Leonardo')

      expect(field('Nome').to_h).to eq(label: 'Nome', canonical_key: 'nome', value: 'Leonardo', origin: 'native', satisfied: true)
    end

    it 'satisfies "E-mail" and "Telefone" from the native columns' do
      contact.update!(email: 'a@b.com', phone_number: '+5521999990000')

      expect(field('E-mail')).to have_attributes(value: 'a@b.com', origin: 'native', satisfied: true)
      expect(field('Telefone')).to have_attributes(value: '+5521999990000', origin: 'native', satisfied: true)
    end

    it 'falls back to custom_attributes when the native value is blank' do
      contact.update!(custom_attributes: { 'Nome' => 'Ana' })

      expect(field('Nome')).to have_attributes(value: 'Ana', origin: 'custom_attribute', satisfied: true)
    end

    it 'reports an unsatisfied field with no value and no origin' do
      expect(field('Nome')).to have_attributes(value: nil, origin: nil, satisfied: false)
      expect(field('Cidade / UF')).not_to be_satisfied
      expect(resolver.missing_labels).to eq(labels)
      expect(resolver.collected).to eq({})
    end

    it 'keeps config order in fields, missing_labels and collected' do
      contact.update!(name: 'Leonardo', custom_attributes: { 'cidade_uf' => 'Rio/RJ' })

      expect(resolver.fields.map(&:label)).to eq(labels)
      expect(resolver.required_canonical_keys).to eq(%w[nome email telefone cidade_uf])
      expect(resolver.missing_labels).to eq(%w[E-mail Telefone])
      expect(resolver.collected).to eq('Nome' => 'Leonardo', 'Cidade / UF' => 'Rio/RJ')
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

      it 'satisfies every config v2 label' do
        contact.update!(custom_attributes: {
                          'tipo_intervencao' => 'sondagem', 'cidade_uf' => 'Rio/RJ', 'endereco_obra' => 'Rua A, 1', 'area' => '800 m²',
                          'profundidade' => '10 m', 'prazo_desejado' => 'amanhã', 'integracao_seguranca' => 'sim',
                          'empresa' => 'ACME', 'email' => 'x@acme.com'
                        })

        expect(resolver.missing_labels).to be_empty
        expect(resolver.fields.map(&:origin).uniq).to eq(['custom_attribute'])
        expect(field('Área ou extensão').value).to eq('800 m²')
      end

      it 'satisfies a label from a custom attribute with different accent and case' do
        contact.update!(custom_attributes: { 'AREA OU EXTENSAO' => '500 m²', 'endereco' => 'Rua B' })

        expect(field('Área ou extensão')).to have_attributes(value: '500 m²', satisfied: true)
        expect(field('Endereço da obra')).to have_attributes(value: 'Rua B', satisfied: true)
      end
    end
  end

  describe 'RF-05: labels outside the alias map' do
    let(:labels) { ['Orçamento'] }

    it 'uses the normalized label as canonical key and matches a normalized custom attribute' do
      contact.update!(custom_attributes: { 'orcamento' => '50k' })

      expect(field('Orçamento')).to have_attributes(canonical_key: 'orcamento', value: '50k', origin: 'custom_attribute', satisfied: true)
    end

    it 'is unsatisfied without a matching custom attribute' do
      expect(field('Orçamento')).not_to be_satisfied
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
  end

  describe 'RF-06: determinism' do
    it 'resolves without LLM, HTTP or message reads, returning equal results on repeated calls' do
      contact.update!(name: 'Leonardo', custom_attributes: { 'cidade' => 'Rio' })
      allow(ScanSolo::TestMode::MockLlmProvider).to receive(:call).and_raise('LLM called')
      allow(RubyLLM).to receive(:chat).and_raise('LLM called')
      allow(Net::HTTP).to receive(:start).and_raise('HTTP called')
      allow(Net::HTTP).to receive(:new).and_raise('HTTP called')
      queries = []
      callback = ->(*, payload) { queries << payload[:sql] }

      results = ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
        Array.new(2) do
          resolved = described_class.call(contact: contact, config: config)
          [resolved.fields.map(&:to_h), resolved.make_qualification]
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
