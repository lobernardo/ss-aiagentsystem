import {
  REPORT_PERIODS,
  formatReportDateTime,
  periodOptions,
} from '../reportPeriods';

// `npm test` runs with TZ=UTC: the browser clock is UTC, the periods are
// São Paulo (UTC−3) calendar days.
describe('reportPeriods', () => {
  it('runs these specs with the process in UTC', () => {
    expect(new Date('2026-11-09T00:00:00Z').getTimezoneOffset()).toBe(0);
  });

  describe('week', () => {
    it('lists the current week and the 2 previous ones, Monday-anchored', () => {
      const options = periodOptions(
        REPORT_PERIODS.WEEK,
        new Date('2026-11-07T13:00:00Z')
      );

      expect(options).toEqual([
        { anchor: '2026-11-02', start: '02/11/2026', end: '08/11/2026' },
        { anchor: '2026-10-26', start: '26/10/2026', end: '01/11/2026' },
        { anchor: '2026-10-19', start: '19/10/2026', end: '25/10/2026' },
      ]);
    });

    it('still reads Sunday 23:59 in São Paulo (02:59 UTC on Monday) as the old week', () => {
      const [current] = periodOptions(
        REPORT_PERIODS.WEEK,
        new Date('2026-11-09T02:59:59Z')
      );

      expect(current.anchor).toBe('2026-11-02');
    });

    it('starts the new week at Monday 00:00 in São Paulo (03:00 UTC)', () => {
      const [current] = periodOptions(
        REPORT_PERIODS.WEEK,
        new Date('2026-11-09T03:00:00Z')
      );

      expect(current).toEqual({
        anchor: '2026-11-09',
        start: '09/11/2026',
        end: '15/11/2026',
      });
    });
  });

  describe('month', () => {
    it('lists the current month and the previous one, anchored on day 1', () => {
      const options = periodOptions(
        REPORT_PERIODS.MONTH,
        new Date('2026-11-07T13:00:00Z')
      );

      expect(options).toEqual([
        { anchor: '2026-11-01', start: '01/11/2026', end: '30/11/2026' },
        { anchor: '2026-10-01', start: '01/10/2026', end: '31/10/2026' },
      ]);
    });

    it('keeps the old month until midnight in São Paulo', () => {
      expect(
        periodOptions(REPORT_PERIODS.MONTH, new Date('2026-12-01T02:59:59Z'))[0]
          .anchor
      ).toBe('2026-11-01');
      expect(
        periodOptions(REPORT_PERIODS.MONTH, new Date('2026-12-01T03:00:00Z'))[0]
          .anchor
      ).toBe('2026-12-01');
    });

    it('crosses the year boundary', () => {
      const options = periodOptions(
        REPORT_PERIODS.MONTH,
        new Date('2027-01-01T03:00:00Z')
      );

      expect(options.map(option => option.anchor)).toEqual([
        '2027-01-01',
        '2026-12-01',
      ]);
    });
  });

  it('formats the snapshot timestamp in São Paulo time', () => {
    expect(formatReportDateTime('2026-11-09T09:00:00Z')).toBe(
      '09/11/2026 06:00'
    );
  });
});
