import { describe, expect, it } from 'vitest';
import { daysUntil, deadlineIndicator, deadlineLevel } from '../src/lib/deadline';
import { parseStatus, statusIndex, statusLabel, TENDER_STATUS_CODES } from '../src/lib/tenderStatus';

const TODAY = new Date('2026-10-07T00:00:00Z');

describe('deadline indicators', () => {
  it('counts whole days to the closing date', () => {
    expect(daysUntil('2026-10-10', TODAY)).toBe(3);
    expect(daysUntil('2026-10-01', TODAY)).toBe(-6);
    expect(daysUntil(null, TODAY)).toBeNull();
  });

  it('marks a passed closing date as overdue (red)', () => {
    const ind = deadlineIndicator('2026-10-01', 'medium', TODAY);
    expect(ind.level).toBe('overdue');
    expect(ind.color).toBe('red');
  });

  it('marks a closing date within 7 days as approaching (yellow)', () => {
    const ind = deadlineIndicator('2026-10-12', 'low', TODAY);
    expect(deadlineLevel('2026-10-12', TODAY)).toBe('soon');
    expect(ind.color).toBe('yellow');
  });

  it('turns high-risk (high/critical) approaching tenders red', () => {
    expect(deadlineIndicator('2026-10-12', 'high', TODAY).color).toBe('red');
    expect(deadlineIndicator('2026-10-12', 'critical', TODAY).color).toBe('red');
  });

  it('marks a distant closing date as normal (green)', () => {
    const ind = deadlineIndicator('2026-10-30', 'medium', TODAY);
    expect(ind.level).toBe('ok');
    expect(ind.color).toBe('green');
  });

  it('marks a missing closing date as grey', () => {
    const ind = deadlineIndicator(null, 'medium', TODAY);
    expect(ind.level).toBe('none');
    expect(ind.color).toBe('grey');
  });
});

describe('tender status pipeline', () => {
  it('has the 13 agreed statuses in order', () => {
    expect(TENDER_STATUS_CODES).toHaveLength(13);
    expect(statusIndex('new')).toBe(0);
    expect(statusIndex('cancelled')).toBe(12);
  });

  it('labels codes for display', () => {
    expect(statusLabel('under_review')).toBe('Under Review');
    expect(statusLabel('commercial_evaluation')).toBe('Commercial Evaluation');
  });

  it('normalises unknown input to new', () => {
    expect(parseStatus('bogus')).toBe('new');
    expect(parseStatus('won')).toBe('won');
  });

  it('sorts unknown codes after known ones', () => {
    expect(statusIndex('not_a_status')).toBe(13);
  });
});
