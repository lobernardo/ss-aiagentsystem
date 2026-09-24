import { mount, flushPromises, enableAutoUnmount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { withFullI18n } from 'test-i18n';
import { useAlert } from 'dashboard/composables';
import ScanSoloContactsAPI from 'dashboard/api/scansoloContacts';
import ContactOptOutCard from '../ContactOptOutCard.vue';

vi.mock('dashboard/api/scansoloContacts', () => ({
  default: { getOptOut: vi.fn(), clearOptOut: vi.fn() },
}));

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

withFullI18n();
enableAutoUnmount(afterEach);

const CONTACT_ID = 31;
const stateResponse = optedOut => ({
  data: { contact_id: CONTACT_ID, opted_out: optedOut },
});

const mountCard = ({ role = 'administrator' } = {}) =>
  mount(ContactOptOutCard, {
    props: { contactId: CONTACT_ID },
    global: {
      plugins: [
        createStore({
          getters: {
            getCurrentRole: () => role,
            getCurrentUser: () => ({ id: 1 }),
          },
        }),
      ],
    },
  });

const removeButton = wrapper =>
  wrapper.find('[data-testid="contact-opt-out-remove"]');

describe('ContactOptOutCard', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    ScanSoloContactsAPI.getOptOut.mockResolvedValue(stateResponse(true));
  });

  it('shows the opted-out state and the remove action to administrators', async () => {
    const wrapper = mountCard();
    await flushPromises();

    expect(ScanSoloContactsAPI.getOptOut).toHaveBeenCalledWith(CONTACT_ID);
    expect(
      wrapper.find('[data-testid="contact-opt-out-state"]').text()
    ).toContain('pediu para não receber mensagens automáticas');
    expect(removeButton(wrapper).text()).toBe('Remover opt-out');
  });

  it('clears the marker with exactly one DELETE after confirmation and re-reads the state', async () => {
    ScanSoloContactsAPI.clearOptOut.mockResolvedValue(stateResponse(false));
    const wrapper = mountCard();
    await flushPromises();
    ScanSoloContactsAPI.getOptOut.mockResolvedValue(stateResponse(false));

    await removeButton(wrapper).trigger('click');
    expect(ScanSoloContactsAPI.clearOptOut).not.toHaveBeenCalled();
    expect(
      wrapper.find('[data-testid="confirm-dialog-message"]').text()
    ).toContain('volta a permitir follow-ups');

    await wrapper
      .find('[data-testid="confirm-dialog-confirm"]')
      .trigger('click');
    await flushPromises();

    expect(ScanSoloContactsAPI.clearOptOut).toHaveBeenCalledTimes(1);
    expect(ScanSoloContactsAPI.clearOptOut).toHaveBeenCalledWith(CONTACT_ID);
    expect(ScanSoloContactsAPI.getOptOut).toHaveBeenCalledTimes(2);
    expect(
      wrapper.find('[data-testid="contact-opt-out-state"]').text()
    ).toContain('recebe follow-ups normalmente');
    expect(removeButton(wrapper).exists()).toBe(false);
    expect(useAlert).toHaveBeenCalledWith('Opt-out removido.');
  });

  it('never calls DELETE when the confirmation is dismissed', async () => {
    const wrapper = mountCard();
    await flushPromises();

    await removeButton(wrapper).trigger('click');
    await wrapper
      .find('[data-testid="confirm-dialog-cancel"]')
      .trigger('click');

    expect(ScanSoloContactsAPI.clearOptOut).not.toHaveBeenCalled();
  });

  it('shows the state to agents without any action control', async () => {
    const wrapper = mountCard({ role: 'agent' });
    await flushPromises();

    expect(wrapper.find('[data-testid="contact-opt-out-state"]').exists()).toBe(
      true
    );
    expect(wrapper.findAll('button')).toHaveLength(0);
  });

  it('shows no action for a contact that is not opted out', async () => {
    ScanSoloContactsAPI.getOptOut.mockResolvedValue(stateResponse(false));
    const wrapper = mountCard();
    await flushPromises();

    expect(
      wrapper.find('[data-testid="contact-opt-out-state"]').text()
    ).toContain('recebe follow-ups normalmente');
    expect(removeButton(wrapper).exists()).toBe(false);
  });

  it('toasts the server message when clearing fails', async () => {
    ScanSoloContactsAPI.clearOptOut.mockRejectedValue({
      response: { data: { error: 'forbidden' } },
    });
    const wrapper = mountCard();
    await flushPromises();

    await removeButton(wrapper).trigger('click');
    await wrapper
      .find('[data-testid="confirm-dialog-confirm"]')
      .trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith('forbidden');
  });

  it('renders the error state when the state cannot be read', async () => {
    ScanSoloContactsAPI.getOptOut.mockRejectedValue(new Error('boom'));
    const wrapper = mountCard();
    await flushPromises();

    expect(wrapper.find('[data-testid="list-state-error"]').exists()).toBe(
      true
    );
  });
});
