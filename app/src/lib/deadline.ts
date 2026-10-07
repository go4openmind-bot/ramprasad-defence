/**
 * Deadline and risk indicators.
 * Green = normal, Yellow = approaching deadline, Red = overdue or high risk.
 * Pure functions so they can be unit-tested with a fixed "today".
 */

export const DEADLINE_WARNING_DAYS = 7;

export type DeadlineLevel = 'overdue' | 'soon' | 'ok' | 'none';
export type IndicatorColor = 'red' | 'yellow' | 'green' | 'grey';

export type TenderPriority = 'low' | 'medium' | 'high' | 'critical';

/** Whole days from today (UTC date) until the due date. Negative = past. */
export function daysUntil(dueDate: string | null | undefined, today: Date = new Date()): number | null {
  if (!dueDate) return null;
  const due = new Date(`${dueDate}T00:00:00Z`);
  if (Number.isNaN(due.getTime())) return null;
  const t = new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), today.getUTCDate()));
  return Math.round((due.getTime() - t.getTime()) / 86_400_000);
}

export function deadlineLevel(
  dueDate: string | null | undefined,
  today: Date = new Date(),
): DeadlineLevel {
  const d = daysUntil(dueDate, today);
  if (d === null) return 'none';
  if (d < 0) return 'overdue';
  if (d <= DEADLINE_WARNING_DAYS) return 'soon';
  return 'ok';
}

export interface DeadlineIndicator {
  level: DeadlineLevel;
  color: IndicatorColor;
  label: string;
  days: number | null;
}

/**
 * The indicator shown in the list and detail pages.
 * Red also covers "high risk": a high/critical priority tender that is already
 * overdue or within the warning window.
 */
export function deadlineIndicator(
  dueDate: string | null | undefined,
  priority: TenderPriority | string | null | undefined,
  today: Date = new Date(),
): DeadlineIndicator {
  const days = daysUntil(dueDate, today);
  const level = deadlineLevel(dueDate, today);
  const highPriority = priority === 'high' || priority === 'critical';

  if (level === 'none') {
    return { level, color: 'grey', label: 'No closing date', days };
  }
  if (level === 'overdue') {
    return { level, color: 'red', label: `Overdue by ${Math.abs(days!)} day(s)`, days };
  }
  if (level === 'soon') {
    const highRisk = highPriority;
    return {
      level,
      color: highRisk ? 'red' : 'yellow',
      label: highRisk
        ? `High risk — ${days} day(s) left`
        : `Due in ${days} day(s)`,
      days,
    };
  }
  return { level, color: 'green', label: `${days} day(s) left`, days };
}

/** Sort key so the most urgent tenders come first. */
export function indicatorRank(color: IndicatorColor): number {
  switch (color) {
    case 'red':
      return 0;
    case 'yellow':
      return 1;
    case 'green':
      return 2;
    default:
      return 3;
  }
}
