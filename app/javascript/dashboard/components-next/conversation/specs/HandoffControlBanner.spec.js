import { mount, flushPromises } from '@vue/test-utils';
import ScanSoloHandoffAPI from 'dashboard/api/scansoloHandoff';
import HandoffControlBanner from '../HandoffControlBanner.vue';

vi.mock('dashboard/api/scansoloHandoff', () => ({
  default: {
    controlState: vi.fn(),
    takeover: vi.fn(),
    returnToAi: vi.fn(),
  },
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

describe('HandoffControlBanner', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    ScanSoloHandoffAPI.controlState.mockResolvedValue({
      data: {
        conversation_id: 1,
        ai_control_state: 'ai_active',
        updated_at: '2026-01-01T09:00:00Z',
      },
    });
  });

  it('shows the current AI-control state label on mount', async () => {
    const wrapper = mount(HandoffControlBanner, {
      props: { conversationId: 1 },
    });
    await flushPromises();

    expect(wrapper.find('[data-testid="control-state-label"]').text()).toBe(
      'SCANSOLO.HANDOFF_BANNER.STATES.AI_ACTIVE'
    );
    expect(wrapper.find('[data-testid="takeover-button"]').exists()).toBe(
      true
    );
    expect(
      wrapper.find('[data-testid="return-to-ai-button"]').exists()
    ).toBe(false);
  });

  it('shows the return-to-AI action once a human has taken over', async () => {
    ScanSoloHandoffAPI.controlState.mockResolvedValue({
      data: {
        conversation_id: 1,
        ai_control_state: 'human_active',
        updated_at: '2026-01-01T09:00:00Z',
      },
    });

    const wrapper = mount(HandoffControlBanner, {
      props: { conversationId: 1 },
    });
    await flushPromises();

    expect(wrapper.find('[data-testid="control-state-label"]').text()).toBe(
      'SCANSOLO.HANDOFF_BANNER.STATES.HUMAN_ACTIVE'
    );
    expect(
      wrapper.find('[data-testid="return-to-ai-button"]').exists()
    ).toBe(true);
    expect(wrapper.find('[data-testid="takeover-button"]').exists()).toBe(
      false
    );
  });

  it('updates immediately after a takeover action, without flicker on repeated clicks', async () => {
    ScanSoloHandoffAPI.takeover.mockResolvedValue({
      data: {
        conversation_id: 1,
        ai_control_state: 'human_active',
        updated_at: '2026-01-01T09:05:00Z',
      },
    });

    const wrapper = mount(HandoffControlBanner, {
      props: { conversationId: 1 },
    });
    await flushPromises();

    await wrapper.find('[data-testid="takeover-button"]').trigger('click');
    await wrapper
      .find('[data-testid="takeover-reason-input"]')
      .setValue('Cliente pediu para falar com humano');

    // Fire two rapid clicks on the confirm button -- only one request should
    // ever be in flight, and the state must land on human_active exactly
    // once with no intermediate/duplicate render.
    const confirmButton = wrapper.find(
      '[data-testid="takeover-confirm-button"]'
    );
    await confirmButton.trigger('click');
    await confirmButton.trigger('click');
    await flushPromises();

    expect(ScanSoloHandoffAPI.takeover).toHaveBeenCalledTimes(1);
    expect(wrapper.find('[data-testid="control-state-label"]').text()).toBe(
      'SCANSOLO.HANDOFF_BANNER.STATES.HUMAN_ACTIVE'
    );
    expect(
      wrapper.find('[data-testid="takeover-reason-dialog"]').exists()
    ).toBe(false);
  });

  it('updates immediately after returning control to AI, without flicker on repeated clicks', async () => {
    ScanSoloHandoffAPI.controlState.mockResolvedValue({
      data: {
        conversation_id: 1,
        ai_control_state: 'human_active',
        updated_at: '2026-01-01T09:00:00Z',
      },
    });
    ScanSoloHandoffAPI.returnToAi.mockResolvedValue({
      data: {
        conversation_id: 1,
        ai_control_state: 'ai_active',
        updated_at: '2026-01-01T09:10:00Z',
      },
    });

    const wrapper = mount(HandoffControlBanner, {
      props: { conversationId: 1 },
    });
    await flushPromises();

    const returnButton = wrapper.find('[data-testid="return-to-ai-button"]');
    await returnButton.trigger('click');
    await returnButton.trigger('click');
    await flushPromises();

    expect(ScanSoloHandoffAPI.returnToAi).toHaveBeenCalledTimes(1);
    expect(wrapper.find('[data-testid="control-state-label"]').text()).toBe(
      'SCANSOLO.HANDOFF_BANNER.STATES.AI_ACTIVE'
    );
    expect(wrapper.find('[data-testid="takeover-button"]').exists()).toBe(
      true
    );
  });

  it('cancelling the takeover reason dialog never calls the API', async () => {
    const wrapper = mount(HandoffControlBanner, {
      props: { conversationId: 1 },
    });
    await flushPromises();

    await wrapper.find('[data-testid="takeover-button"]').trigger('click');
    await wrapper
      .find('[data-testid="takeover-cancel-button"]')
      .trigger('click');

    expect(
      wrapper.find('[data-testid="takeover-reason-dialog"]').exists()
    ).toBe(false);
    expect(ScanSoloHandoffAPI.takeover).not.toHaveBeenCalled();
  });
});
