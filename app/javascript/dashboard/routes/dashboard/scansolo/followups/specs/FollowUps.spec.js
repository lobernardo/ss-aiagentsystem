import { mount, flushPromises } from '@vue/test-utils';
import { createPinia, setActivePinia } from 'pinia';
import ScanSoloCadenceEnrollmentsAPI from 'dashboard/api/scansoloCadenceEnrollments';
import FollowUps from '../FollowUps.vue';

vi.mock('dashboard/api/scansoloCadenceEnrollments', () => ({
  default: {
    get: vi.fn(),
    pause: vi.fn(),
    resume: vi.fn(),
    cancel: vi.fn(),
  },
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

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
  });

  it('shows active cadence enrollments with contact, current step and next attempt (UI-07)', async () => {
    const wrapper = mount(FollowUps);
    await flushPromises();

    const row = enrollmentRow(wrapper, activeEnrollment.id);
    expect(row.exists()).toBe(true);
    expect(row.find('[data-testid="enrollment-contact-name"]').text()).toBe(
      'Maria Silva'
    );
    expect(row.find('[data-testid="enrollment-current-step"]').text()).toBe(
      '1'
    );
    expect(row.find('[data-testid="enrollment-next-attempt"]').text()).toBe(
      '2026-01-05T12:00:00Z'
    );
    expect(row.find('[data-testid="enrollment-status"]').text()).toBe(
      'SCANSOLO.FOLLOW_UPS.STATUSES.ACTIVE'
    );
  });

  it('shows an empty state when there are no active enrollments', async () => {
    ScanSoloCadenceEnrollmentsAPI.get.mockResolvedValue({ data: [] });

    const wrapper = mount(FollowUps);
    await flushPromises();

    expect(
      wrapper.find('[data-testid="follow-ups-empty-state"]').exists()
    ).toBe(true);
  });

  it('pauses an active enrollment and reflects the persisted state (RF-64)', async () => {
    ScanSoloCadenceEnrollmentsAPI.pause.mockResolvedValue({
      data: { ...activeEnrollment, status: 'paused', next_attempt_at: null },
    });

    const wrapper = mount(FollowUps);
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
      'SCANSOLO.FOLLOW_UPS.STATUSES.PAUSED'
    );
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

    const wrapper = mount(FollowUps);
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
    ).toBe('SCANSOLO.FOLLOW_UPS.STATUSES.ACTIVE');
  });

  it('cancels an enrollment, hiding the pause/resume/cancel controls once cancelled', async () => {
    ScanSoloCadenceEnrollmentsAPI.cancel.mockResolvedValue({
      data: { ...activeEnrollment, status: 'cancelled', next_attempt_at: null },
    });

    const wrapper = mount(FollowUps);
    await flushPromises();

    await enrollmentRow(wrapper, activeEnrollment.id)
      .find('[data-testid="cancel-button"]')
      .trigger('click');
    await flushPromises();

    expect(ScanSoloCadenceEnrollmentsAPI.cancel).toHaveBeenCalledWith(
      activeEnrollment.id
    );
    const row = enrollmentRow(wrapper, activeEnrollment.id);
    expect(row.find('[data-testid="enrollment-status"]').text()).toBe(
      'SCANSOLO.FOLLOW_UPS.STATUSES.CANCELLED'
    );
    expect(row.find('[data-testid="cancel-button"]').exists()).toBe(false);
  });
});
