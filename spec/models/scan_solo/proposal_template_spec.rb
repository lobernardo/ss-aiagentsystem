# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::ProposalTemplate do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:sha256) { 'a' * 64 }
  let(:template) do
    described_class.new(account: account, uploaded_by: admin, filename: 'proposta.docx', byte_size: 7, sha256: sha256).tap do |record|
      record.file.attach(io: StringIO.new('PK-docx'), filename: 'proposta.docx',
                         content_type: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document')
    end
  end

  describe 'CT-06: validations' do
    it 'is valid with filename, byte_size, a 64-hex sha256 and an attached file' do
      expect(template).to be_valid
    end

    it 'is invalid without an attached file' do
      record = described_class.new(account: account, filename: 'proposta.docx', byte_size: 7, sha256: sha256)

      expect(record).not_to be_valid
      expect(record.errors[:file]).to be_present
    end

    it 'is invalid with a sha256 outside 64 hex characters' do
      ['a' * 63, "#{'a' * 63}z", 'a' * 65].each do |value|
        template.sha256 = value

        expect(template).not_to be_valid
        expect(template.errors[:sha256]).to be_present
      end
    end

    it 'requires filename and byte_size' do
      template.assign_attributes(filename: nil, byte_size: nil)

      expect(template).not_to be_valid
      expect(template.errors.attribute_names).to include(:filename, :byte_size)
    end

    it 'accepts a template without uploader (user deleted → nullified)' do
      template.uploaded_by = nil

      expect(template).to be_valid
    end
  end

  describe 'RF-21: active_for is scoped by account' do
    it 'returns the active template of the account and nil for another account' do
      template.update!(active: true)

      expect(described_class.active_for(account)).to eq(template)
      expect(described_class.active_for(other_account)).to be_nil
    end

    it 'returns nil when the account has only inactive templates' do
      template.save!

      expect(described_class.active_for(account)).to be_nil
    end
  end

  describe 'template_version' do
    it 'is "<id>:<sha256>"' do
      template.update!(active: true)

      expect(template.template_version).to eq("#{template.id}:#{sha256}")
      expect(template.template_version).to match(/\A\d+:\h{64}\z/)
    end
  end
end
