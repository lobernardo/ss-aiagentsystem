# frozen_string_literal: true

require 'rails_helper'

# RF-11 / RNF-01: there is no debounce window. While the first turn is still
# inside its (slow) model call, two more customer messages arrive within two
# seconds; their jobs hit the per-conversation mutex and are re-enqueued.
# Only the turn of the latest message answers, with the whole burst in its
# history.
RSpec.describe 'ScanSolo burst of incoming messages' do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:provider_name) { 'ScanSoloBurstSlowProvider' }
  let(:burst) { [] }

  before do
    draft = ScanSolo::AiAgentConfig.draft_for!(account)
    draft.update!(name: 'Agente ScanSolo', enabled: true, allowed_inbox_ids: [inbox.id])
    ScanSolo::AiAgent::PublishService.new(account: account).call

    stub_const(provider_name, slow_provider)
  end

  def incoming(content)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, sender: contact,
                     content: content)
  end

  # The first model call is the "slow" one: messages 2 and 3 arrive (1 s
  # apart) and their jobs start while it is still running.
  def slow_provider
    spec = self
    Class.new do
      define_singleton_method(:call) do |**kwargs|
        spec.arrive_during_model_call! if spec.burst.size == 1
        ScanSolo::TestMode::MockLlmProvider.call(**kwargs)
      end
    end
  end

  def arrive_during_model_call!
    %w[segunda-mensagem terceira-mensagem].each do |content|
      travel(1.second)
      burst << incoming(content)
      ScanSolo::AiTurnJob.perform_now(burst.last.id, llm_provider: provider_name)
    end
  end

  it 'sends exactly one reply, supersedes the two older turns and answers with every burst message in the payload' do
    burst << incoming('primeira-mensagem')

    ScanSolo::AiTurnJob.perform_now(burst.first.id, llm_provider: provider_name)
    expect(enqueued_jobs.count { |job| job['job_class'] == 'ScanSolo::AiTurnJob' }).to eq(2)
    perform_enqueued_jobs(only: ScanSolo::AiTurnJob)

    turns = burst.map { |message| ScanSolo::AiTurn.find_by!(message_id: message.id) }
    expect(turns.map(&:invocation_status)).to eq(%w[suppressed suppressed succeeded])
    expect(turns.first(2).map(&:failure_reason)).to eq(%w[superseded superseded])
    expect(conversation.messages.outgoing.where(private: false).count).to eq(1)
    expect(ScanSolo::TestMode::MockLlmProvider.last_payload[:messages].pluck(:content))
      .to include('primeira-mensagem', 'segunda-mensagem', 'terceira-mensagem')
  end
end
