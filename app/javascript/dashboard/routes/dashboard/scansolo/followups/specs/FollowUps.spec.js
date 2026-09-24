import { mount, flushPromises, enableAutoUnmount } from '@vue/test-utils';
import { createPinia, setActivePinia } from 'pinia';
import { createStore } from 'vuex';
import { withFullI18n } from 'test-i18n';
import { useAlert } from 'dashboard/composables';
import ScanSoloCadenceEnrollmentsAPI from 'dashboard/api/scansoloCadenceEnrollments';
import ScanSoloCadenceTemplatesAPI from 'dashboard/api/scansoloCadenceTemplates';
import FollowUps from '../FollowUps.vue';

vi.mock('dashboard/api/scansoloCadenceEnrollments', () => ({
  default: {
    get: vi.fn(),
    pause: vi.fn(),
    resume: vi.fn(),
    cancel: vi.fn(),
  },
}));

vi.mock('dashboard/api/scansoloCadenceTemplates', () => ({
  default: { get: vi.fn(), update: vi.fn() },
}));

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

withFullI18n();
enableAutoUnmount(afterEach);

const mountFollowUps = () =>
  mount(FollowUps, {
    global: {
      plugins: [
        createStore({
          getters: {
            getCurrentRole: () => 'administrator',
            getCurrentUser: () => ({ id: 1 }),
          },
        }),
      ],
    },
  });

const activeEnrollment = {
  id: 11,
  opportunity_id: 3,
  cadence_definition_id: 1,
  status: 'active',
  current_step: 1,
  next_attempt_at: '2026-01-05T12:00:00Z',
  contact_name: 'Maria Silva',
  cadence_stage: 'novo_lead',
  cadence_version: 1,
};

const enrollmentRow = (wrapper, id) =>
  wrapper.find(`[data-testid="enrollment-row"][data-enrollment-id="${id}"]`);

describe('FollowUps', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
    ScanSoloCadenceEnrollmentsAPI.get.mockResolvedValue({
      data: [activeEnrollment],
    });
    ScanSoloCadenceTemplatesAPI.get.mockResolvedValue({ data: [] });
  });

  it('shows active cadence enrollments with contact, current step and next attempt (UI-07)', async () => {
    const wrapper = mountFollowUps();
    await flushPromises();

    const row = enrollmentRow(wrapper, activeEnrollment.id);
    expect(row.exists()).toBe(true);
    expect(row.find('[data-testid="enrollment-contact-name"]').text()).toBe(
      'Maria Silva'
    );
    expect(row.find('[data-testid="enrollment-current-step"]').text()).toBe(
      '1'
    );
    expect(
      row.find('[data-testid="enrollment-next-attempt"]').attributes('title')
    ).toBe('05/01/2026 12:00');
    expect(row.html()).not.toContain('2026-01-05T');
    expect(row.find('[data-testid="enrollment-status"]').text()).toBe('Ativa');
  });

  it('shows an empty state when there are no active enrollments', async () => {
    ScanSoloCadenceEnrollmentsAPI.get.mockResolvedValue({ data: [] });

    const wrapper = mountFollowUps();
    await flushPromises();

    expect(wrapper.find('[data-testid="list-state-empty"]').text()).toBe(
      'Nenhuma cadência de follow-up ativa no momento.'
    );
  });

  it('pauses an active enrollment and reflects the persisted state (RF-64)', async () => {
    ScanSoloCadenceEnrollmentsAPI.pause.mockResolvedValue({
      data: { ...activeEnrollment, status: 'paused', next_attempt_at: null },
    });

    const wrapper = mountFollowUps();
    await flushPromises();

    await enrollmentRow(wrapper, activeEnrollment.id)
      .find('[data-testid="pause-button"]')
      .trigger('click');
    await flushPromises();

    expect(ScanSoloCadenceEnrollmentsAPI.pause).toHaveBeenCalledWith(
      activeEnrollment.id
    );
    const row = enrollmentRow(wrapper, activeEnrollment.id);
    expect(row.find('[data-testid="enrollment-status"]').text()).toBe(
      'Pausada'
    );
    expect(useAlert).toHaveBeenCalledWith('Follow-up pausado.');
    expect(row.find('[data-testid="resume-button"]').exists()).toBe(true);
    expect(row.find('[data-testid="pause-button"]').exists()).toBe(false);
  });

  it('resumes a paused enrollment', async () => {
    ScanSoloCadenceEnrollmentsAPI.get.mockResolvedValue({
      data: [{ ...activeEnrollment, status: 'paused', next_attempt_at: null }],
    });
    ScanSoloCadenceEnrollmentsAPI.resume.mockResolvedValue({
      data: activeEnrollment,
    });

    const wrapper = mountFollowUps();
    await flushPromises();

    await enrollmentRow(wrapper, activeEnrollment.id)
      .find('[data-testid="resume-button"]')
      .trigger('click');
    await flushPromises();

    expect(ScanSoloCadenceEnrollmentsAPI.resume).toHaveBeenCalledWith(
      activeEnrollment.id
    );
    expect(
      enrollmentRow(wrapper, activeEnrollment.id)
        .find('[data-testid="enrollment-status"]')
        .text()
    ).toBe('Ativa');
  });

  it('cancels an enrollment only after confirmation, hiding the controls once cancelled', async () => {
    ScanSoloCadenceEnrollmentsAPI.cancel.mockResolvedValue({
      data: { ...activeEnrollment, status: 'cancelled', next_attempt_at: null },
    });

    const wrapper = mountFollowUps();
    await flushPromises();

    await enrollmentRow(wrapper, activeEnrollment.id)
      .find('[data-testid="cancel-button"]')
      .trigger('click');
    await flushPromises();

    expect(ScanSoloCadenceEnrollmentsAPI.cancel).not.toHaveBeenCalled();
    expect(
      wrapper.find('[data-testid="confirm-dialog-message"]').text()
    ).toContain('Maria Silva');

    await wrapper
      .find('[data-testid="confirm-dialog-confirm"]')
      .trigger('click');
    await flushPromises();

    expect(ScanSoloCadenceEnrollmentsAPI.cancel).toHaveBeenCalledWith(
      activeEnrollment.id
    );
    const row = enrollmentRow(wrapper, activeEnrollment.id);
    expect(row.find('[data-testid="enrollment-status"]').text()).toBe(
      'Cancelada'
    );
    expect(row.find('[data-testid="cancel-button"]').exists()).toBe(false);
  });

  it('keeps the follow-up when the cancel confirmation is dismissed', async () => {
    const wrapper = mountFollowUps();
    await flushPromises();

    await enrollmentRow(wrapper, activeEnrollment.id)
      .find('[data-testid="cancel-button"]')
      .trigger('click');
    await wrapper
      .find('[data-testid="confirm-dialog-cancel"]')
      .trigger('click');

    expect(ScanSoloCadenceEnrollmentsAPI.cancel).not.toHaveBeenCalled();
  });

  it('renders the loading and error states (UI-09)', async () => {
    ScanSoloCadenceEnrollmentsAPI.get.mockReturnValueOnce(
      new Promise(() => {})
    );
    const loading = mountFollowUps();
    await flushPromises();
    expect(loading.find('[data-testid="list-state-loading"]').exists()).toBe(
      true
    );

    ScanSoloCadenceEnrollmentsAPI.get.mockRejectedValueOnce(new Error('boom'));
    const failed = mountFollowUps();
    await flushPromises();
    expect(failed.find('[data-testid="list-state-error"]').exists()).toBe(true);
  });

  it('toasts the server message when an action fails', async () => {
    ScanSoloCadenceEnrollmentsAPI.pause.mockRejectedValue({
      response: { data: { error: 'forbidden' } },
    });
    const wrapper = mountFollowUps();
    await flushPromises();

    await enrollmentRow(wrapper, activeEnrollment.id)
      .find('[data-testid="pause-button"]')
      .trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith('forbidden');
  });

  it('mounts the templates panel', async () => {
    const wrapper = mountFollowUps();
    await flushPromises();

    expect(wrapper.find('[data-testid="templates-panel"]').exists()).toBe(true);
  });
});
