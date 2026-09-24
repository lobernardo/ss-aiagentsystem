import { mount, flushPromises } from '@vue/test-utils';
import { computed, ref } from 'vue';
import { createPinia, setActivePinia } from 'pinia';
import { createStore } from 'vuex';
import { withFullI18n } from 'test-i18n';
import ScanSoloHandoffAPI from 'dashboard/api/scansoloHandoff';
import ScanSoloAiAgentConfigAPI from 'dashboard/api/scansoloAiAgentConfig';
import HandoffControlBanner from '../HandoffControlBanner.vue';

vi.mock('dashboard/api/scansoloHandoff', () => ({
  default: {
    controlState: vi.fn(),
    takeover: vi.fn(),
    returnToAi: vi.fn(),
  },
}));

vi.mock('dashboard/api/scansoloAiAgentConfig', () => ({
  default: { get: vi.fn() },
}));

const account = ref({ id: 1, scansolo_enabled: true });
const isAdmin = ref(true);

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ currentAccount: computed(() => account.value) }),
}));

vi.mock('dashboard/composables/useAdmin', () => ({
  useAdmin: () => ({ isAdmin: computed(() => isAdmin.value) }),
}));

withFullI18n();

const CURRENT_USER_ID = 5;

const conversationFixture = (overrides = {}) => ({
  id: 1,
  inbox_id: 7,
  meta: { assignee: null },
  messages: [
    { id: 100, message_type: 0, private: false, sender_type: 'Contact' },
  ],
  ...overrides,
});

const stateResponse = aiControlState => ({
  data: { conversation_id: 1, ai_control_state: aiControlState },
});

const mountBanner = (conversation = conversationFixture()) =>
  mount(HandoffControlBanner, {
    props: { conversation },
    global: {
      plugins: [
        createStore({
          getters: { getCurrentUser: () => ({ id: CURRENT_USER_ID }) },
        }),
      ],
    },
  });

const label = wrapper =>
  wrapper.find('[data-testid="control-state-label"]').text();
const takeoverButton = wrapper =>
  wrapper.find('[data-testid="takeover-button"]');
const returnButton = wrapper =>
  wrapper.find('[data-testid="return-to-ai-button"]');

describe('HandoffControlBanner', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    account.value = { id: 1, scansolo_enabled: true };
    isAdmin.value = true;
    ScanSoloAiAgentConfigAPI.get.mockResolvedValue({
      data: {
        draft: { id: 1, allowed_inbox_ids: [7] },
        published: { id: 2, allowed_inbox_ids: [7] },
        available_models: [],
      },
    });
    ScanSoloHandoffAPI.controlState.mockResolvedValue(
      stateResponse('ai_active')
    );
  });

  it('renders nothing and calls no API when the account flag is off', async () => {
    account.value = { id: 1, scansolo_enabled: false };
    const wrapper = mountBanner();
    await flushPromises();

    expect(
      wrapper.find('[data-testid="handoff-control-banner"]').exists()
    ).toBe(false);
    expect(ScanSoloAiAgentConfigAPI.get).not.toHaveBeenCalled();
    expect(ScanSoloHandoffAPI.controlState).not.toHaveBeenCalled();
  });

  it('renders nothing when the inbox is not in the published allowlist', async () => {
    const wrapper = mountBanner(conversationFixture({ inbox_id: 8 }));
    await flushPromises();

    expect(
      wrapper.find('[data-testid="handoff-control-banner"]').exists()
    ).toBe(false);
    expect(ScanSoloHandoffAPI.controlState).not.toHaveBeenCalled();
  });

  it('shows the takeover action only while the AI is active', async () => {
    const wrapper = mountBanner();
    await flushPromises();

    expect(label(wrapper)).toBe('IA respondendo automaticamente');
    expect(takeoverButton(wrapper).text()).toBe('Assumir conversa');
    expect(returnButton(wrapper).exists()).toBe(false);
  });

  it.each([
    ['human_active', 'Atendimento humano em andamento'],
    ['awaiting_human', 'Aguardando atendimento humano'],
  ])('shows the return action only in %s', async (state, stateLabel) => {
    ScanSoloHandoffAPI.controlState.mockResolvedValue(stateResponse(state));
    const wrapper = mountBanner();
    await flushPromises();

    expect(label(wrapper)).toBe(stateLabel);
    expect(returnButton(wrapper).text()).toBe('Retornar para IA');
    expect(takeoverButton(wrapper).exists()).toBe(false);
  });

  it.each(['handoff_requested', 'paused', 'closed'])(
    'shows no action in %s',
    async state => {
      ScanSoloHandoffAPI.controlState.mockResolvedValue(stateResponse(state));
      const wrapper = mountBanner();
      await flushPromises();

      expect(label(wrapper)).not.toContain('SCANSOLO.');
      expect(takeoverButton(wrapper).exists()).toBe(false);
      expect(returnButton(wrapper).exists()).toBe(false);
    }
  );

  it('disables the action for a non-administrator who is not the assignee', async () => {
    isAdmin.value = false;
    const wrapper = mountBanner(
      conversationFixture({ meta: { assignee: { id: 99 } } })
    );
    await flushPromises();

    expect(takeoverButton(wrapper).attributes('disabled')).toBeDefined();
  });

  it('enables the action for the assignee', async () => {
    isAdmin.value = false;
    const wrapper = mountBanner(
      conversationFixture({ meta: { assignee: { id: CURRENT_USER_ID } } })
    );
    await flushPromises();

    expect(takeoverButton(wrapper).attributes('disabled')).toBeUndefined();
  });

  it('refetches the state after a takeover, without double requests', async () => {
    ScanSoloHandoffAPI.takeover.mockResolvedValue(
      stateResponse('human_active')
    );
    const wrapper = mountBanner();
    await flushPromises();
    ScanSoloHandoffAPI.controlState.mockResolvedValue(
      stateResponse('human_active')
    );

    await takeoverButton(wrapper).trigger('click');
    const confirm = wrapper.find('[data-testid="takeover-confirm-button"]');
    await confirm.trigger('click');
    await confirm.trigger('click');
    await flushPromises();

    expect(ScanSoloHandoffAPI.takeover).toHaveBeenCalledTimes(1);
    expect(ScanSoloHandoffAPI.controlState).toHaveBeenCalledTimes(2);
    expect(label(wrapper)).toBe('Atendimento humano em andamento');
    expect(returnButton(wrapper).exists()).toBe(true);
  });

  it('refetches the state after returning control to the AI', async () => {
    ScanSoloHandoffAPI.controlState.mockResolvedValue(
      stateResponse('human_active')
    );
    ScanSoloHandoffAPI.returnToAi.mockResolvedValue(stateResponse('ai_active'));
    const wrapper = mountBanner();
    await flushPromises();
    ScanSoloHandoffAPI.controlState.mockResolvedValue(
      stateResponse('ai_active')
    );

    const button = returnButton(wrapper);
    await button.trigger('click');
    await button.trigger('click');
    await flushPromises();

    expect(ScanSoloHandoffAPI.returnToAi).toHaveBeenCalledTimes(1);
    expect(label(wrapper)).toBe('IA respondendo automaticamente');
  });

  it('cancelling the takeover reason dialog never calls the API', async () => {
    const wrapper = mountBanner();
    await flushPromises();

    await takeoverButton(wrapper).trigger('click');
    await wrapper
      .find('[data-testid="takeover-cancel-button"]')
      .trigger('click');

    expect(ScanSoloHandoffAPI.takeover).not.toHaveBeenCalled();
    expect(
      wrapper.find('[data-testid="takeover-reason-dialog"]').exists()
    ).toBe(false);
  });

  it('shows human_active after an agent reply, without reload', async () => {
    const conversation = conversationFixture();
    const wrapper = mountBanner(conversation);
    await flushPromises();
    ScanSoloHandoffAPI.controlState.mockResolvedValue(
      stateResponse('human_active')
    );

    await wrapper.setProps({
      conversation: {
        ...conversation,
        messages: [
          ...conversation.messages,
          { id: 101, message_type: 1, private: false, sender_type: 'User' },
        ],
      },
    });
    await flushPromises();

    expect(label(wrapper)).toBe('Atendimento humano em andamento');
    expect(returnButton(wrapper).exists()).toBe(true);
  });

  it('keeps reading until the async implicit takeover lands', async () => {
    vi.useFakeTimers();
    const conversation = conversationFixture();
    const wrapper = mountBanner(conversation);
    await flushPromises();
    ScanSoloHandoffAPI.controlState
      .mockResolvedValueOnce(stateResponse('ai_active'))
      .mockResolvedValue(stateResponse('human_active'));

    await wrapper.setProps({
      conversation: {
        ...conversation,
        messages: [
          ...conversation.messages,
          { id: 101, message_type: 1, private: false, sender_type: 'User' },
        ],
      },
    });
    await flushPromises();
    expect(label(wrapper)).toBe('IA respondendo automaticamente');

    await vi.advanceTimersByTimeAsync(1000);
    await flushPromises();

    expect(label(wrapper)).toBe('Atendimento humano em andamento');
    vi.useRealTimers();
  });

  it('ignores private notes and AI messages', async () => {
    const conversation = conversationFixture();
    const wrapper = mountBanner(conversation);
    await flushPromises();

    await wrapper.setProps({
      conversation: {
        ...conversation,
        messages: [
          ...conversation.messages,
          { id: 101, message_type: 1, private: true, sender_type: 'User' },
          { id: 102, message_type: 1, private: false, sender_type: null },
        ],
      },
    });
    await flushPromises();

    expect(ScanSoloHandoffAPI.controlState).toHaveBeenCalledTimes(1);
  });
});
