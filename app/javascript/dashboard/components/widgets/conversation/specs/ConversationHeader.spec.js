import { shallowMount, enableAutoUnmount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { withFullI18n } from 'test-i18n';
import axios from 'axios';
import Button from 'next/button/Button.vue';
import ConversationHeader from '../ConversationHeader.vue';

const { route, push } = vi.hoisted(() => ({
  route: { name: 'inbox_conversation', params: {} },
  push: vi.fn(),
}));

vi.mock('vue-router', () => ({
  useRoute: () => route,
  useRouter: () => ({ push }),
}));
// BackButton imports the application router; navigation is isolated here.
vi.mock('dashboard/routes/index', () => ({ default: { push: vi.fn() } }));
vi.mock('axios');

withFullI18n();
enableAutoUnmount(afterEach);

describe('ConversationHeader', () => {
  let wrapper;
  let store;
  let chat;

  beforeEach(() => {
    route.name = 'inbox_conversation';
    route.params = { accountId: '1', conversation_id: '42' };
    chat = {
      id: 42,
      inbox_id: 7,
      status: 'open',
      ai_control_state: 'human_active',
      meta: { sender: { id: 5 }, assignee: { id: 9 }, team: { id: 3 } },
    };
    const inbox = { id: 7, name: 'Support', channel_type: 'Channel::Whatsapp' };
    store = createStore({
      getters: {
        getSelectedChat: () => chat,
        getCurrentAccountId: () => 1,
        'contacts/getContact': () => () => ({ id: 5, name: 'Lead' }),
        'inboxes/getInbox': () => () => inbox,
        'inboxes/getInboxById': () => () => inbox,
        'inboxes/getInboxes': () => [inbox],
      },
    });
    wrapper = shallowMount(ConversationHeader, {
      props: { chat },
      global: {
        plugins: [store],
        stubs: { Button: false, FluentIcon: true },
      },
    });
  });

  it('shows an accessible X in the non-expanded layout', () => {
    const closeButton = wrapper.get(
      '[data-testid="conversation-close-button"]'
    );

    expect(closeButton.isVisible()).toBe(true);
    expect(closeButton.attributes('aria-label')).toBe('Close');
    expect(closeButton.attributes('title')).toBe('Close');
    expect(wrapper.getComponent(Button).props('icon')).toBe('i-lucide-x');
    expect(wrapper.findComponent({ name: 'BackButton' }).exists()).toBe(false);
  });

  it.each([
    [{}, 'inbox_conversation', '/app/accounts/1/dashboard'],
    [{ inbox_id: '7' }, 'inbox_conversation', '/app/accounts/1/inbox/7'],
    [
      { label: 'priority' },
      'conversation_through_label',
      '/app/accounts/1/label/priority',
    ],
    [{ teamId: '3' }, 'conversation_through_team', '/app/accounts/1/team/3'],
    [
      { id: '8' },
      'conversation_through_custom_view',
      '/app/accounts/1/custom_view/8',
    ],
    [
      {},
      'conversation_through_mentions',
      '/app/accounts/1/mentions/conversations',
    ],
    [
      {},
      'conversation_through_participating',
      '/app/accounts/1/participating/conversations',
    ],
    [
      {},
      'conversation_through_unattended',
      '/app/accounts/1/unattended/conversations',
    ],
  ])(
    'closes to the current list %s without API calls or state changes',
    async (params, name, url) => {
      // The URL is lazy: these route values are read when the button is clicked.
      route.params = { ...route.params, ...params };
      route.name = name;
      const originalChat = structuredClone(chat);
      const dispatch = vi.spyOn(store, 'dispatch');
      const commit = vi.spyOn(store, 'commit');

      await wrapper
        .get('[data-testid="conversation-close-button"]')
        .trigger('click');

      expect(push).toHaveBeenCalledExactlyOnceWith(url);
      expect(axios).not.toHaveBeenCalled();
      ['request', 'get', 'post', 'put', 'patch', 'delete'].forEach(method => {
        expect(axios[method]).not.toHaveBeenCalled();
      });
      expect(dispatch).not.toHaveBeenCalled();
      expect(commit).not.toHaveBeenCalled();
      expect(chat).toEqual(originalChat);
    }
  );

  it('keeps BackButton and hides X in the expanded layout', async () => {
    await wrapper.setProps({ showBackButton: true });

    expect(
      wrapper.find('[data-testid="conversation-close-button"]').exists()
    ).toBe(false);
    expect(wrapper.getComponent({ name: 'BackButton' }).props('backUrl')).toBe(
      '/app/accounts/1/dashboard'
    );
    expect(push).not.toHaveBeenCalled();
  });
});
