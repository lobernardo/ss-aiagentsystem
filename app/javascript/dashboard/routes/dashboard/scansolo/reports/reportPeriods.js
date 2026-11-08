import {
  endOfMonth,
  endOfWeek,
  format,
  startOfMonth,
  startOfWeek,
  subMonths,
  subWeeks,
} from 'date-fns';
import { formatInTimeZone, utcToZonedTime } from 'date-fns-tz';

// UI-02: periods are always computed in the business time zone, whatever the
// browser's, mirroring ScanSolo::Reports::Period (Monday-start weeks).
export const REPORT_TIME_ZONE = 'America/Sao_Paulo';

export const REPORT_PERIODS = { WEEK: 'week', MONTH: 'month' };

const WEEK_OPTIONS_COUNT = 3;
const MONTH_OPTIONS_COUNT = 2;
const WEEK_STARTS_ON_MONDAY = { weekStartsOn: 1 };
const ANCHOR_FORMAT = 'yyyy-MM-dd';
const DATE_LABEL_FORMAT = 'dd/MM/yyyy';
const DATE_TIME_LABEL_FORMAT = 'dd/MM/yyyy HH:mm';

// `utcToZonedTime` returns a Date whose local fields read as São Paulo wall
// time, so the date-fns helpers below work on São Paulo calendar days.
const buildOption = (start, end) => ({
  anchor: format(start, ANCHOR_FORMAT),
  start: format(start, DATE_LABEL_FORMAT),
  end: format(end, DATE_LABEL_FORMAT),
});

const weekOptions = zonedNow =>
  Array.from({ length: WEEK_OPTIONS_COUNT }, (_, index) => {
    const day = subWeeks(zonedNow, index);
    return buildOption(
      startOfWeek(day, WEEK_STARTS_ON_MONDAY),
      endOfWeek(day, WEEK_STARTS_ON_MONDAY)
    );
  });

const monthOptions = zonedNow =>
  Array.from({ length: MONTH_OPTIONS_COUNT }, (_, index) => {
    const day = subMonths(zonedNow, index);
    return buildOption(startOfMonth(day), endOfMonth(day));
  });

// Current period first. `anchor` is the period's first day (Monday / day 1);
// `start`/`end` are the inclusive first and last days, in pt-BR format.
export const periodOptions = (period, now = new Date()) => {
  const zonedNow = utcToZonedTime(now, REPORT_TIME_ZONE);
  return period === REPORT_PERIODS.MONTH
    ? monthOptions(zonedNow)
    : weekOptions(zonedNow);
};

// UI-03: "dados congelados em <generated_at>", in São Paulo time.
export const formatReportDateTime = value =>
  formatInTimeZone(new Date(value), REPORT_TIME_ZONE, DATE_TIME_LABEL_FORMAT);
