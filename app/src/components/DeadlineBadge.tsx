import { deadlineIndicator } from '@/lib/deadline';
import type { TenderPriority } from '@/lib/deadline';

/**
 * Green = normal, Yellow = approaching deadline, Red = overdue / high risk.
 * Renders a small coloured pill with a plain-language label.
 */
export function DeadlineBadge({
  dueDate,
  priority,
  today,
}: {
  dueDate: string | null | undefined;
  priority: TenderPriority | string | null | undefined;
  today?: Date;
}) {
  const ind = deadlineIndicator(dueDate, priority, today);
  return (
    <span className={`badge ${ind.color}`} title={ind.label}>
      {ind.label}
    </span>
  );
}
