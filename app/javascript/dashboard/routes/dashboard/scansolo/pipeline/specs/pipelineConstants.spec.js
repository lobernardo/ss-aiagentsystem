import { isStaleOpportunity } from '../pipelineConstants';

// Same cases (and the same `now`) as the Ruby spec of
// ScanSolo::Pipeline::OpportunityQuery.stale? (Relatórios RF-04 (a)–(c)).
const NOW = new Date('2026-11-08T12:00:00Z');
const MINUTE_MS = 60 * 1000;
const HOUR_MS = 60 * MINUTE_MS;
const DAY_MS = 24 * HOUR_MS;
const ago = ms => new Date(NOW.getTime() - ms).toISOString();

const opportunity = attributes => ({
  stage: 'novo_lead',
  lastCustomerInteractionAt: null,
  createdAt: ago(10 * DAY_MS),
  ...attributes,
});

describe('isStaleOpportunity', () => {
  it.each([
    [
      '(a) last interaction 47 h 59 min ago',
      { lastCustomerInteractionAt: ago(47 * HOUR_MS + 59 * MINUTE_MS) },
      false,
    ],
    [
      '(a) last interaction exactly 48 h ago',
      { lastCustomerInteractionAt: ago(48 * HOUR_MS) },
      true,
    ],
    [
      '(b) no interaction, created exactly 48 h ago',
      { createdAt: ago(48 * HOUR_MS) },
      true,
    ],
    [
      '(b) no interaction, created 47 h 59 min ago',
      { createdAt: ago(47 * HOUR_MS + 59 * MINUTE_MS) },
      false,
    ],
    [
      '(c) ganho with the last interaction 30 days ago',
      {
        stage: 'ganho',
        lastCustomerInteractionAt: ago(30 * DAY_MS),
        createdAt: ago(30 * DAY_MS),
      },
      false,
    ],
    [
      '(c) perdido with the last interaction 30 days ago',
      {
        stage: 'perdido',
        lastCustomerInteractionAt: ago(30 * DAY_MS),
        createdAt: ago(30 * DAY_MS),
      },
      false,
    ],
  ])('%s → %s', (_name, attributes, expected) => {
    expect(isStaleOpportunity(opportunity(attributes), NOW)).toBe(expected);
  });

  it('prefers the last interaction over created_at', () => {
    expect(
      isStaleOpportunity(
        opportunity({
          lastCustomerInteractionAt: ago(HOUR_MS),
          createdAt: ago(30 * DAY_MS),
        }),
        NOW
      )
    ).toBe(false);
  });
});
