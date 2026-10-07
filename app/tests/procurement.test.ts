import { describe, expect, it } from 'vitest';
import { deliveryRisk, isReadyForDispatch, labelFor, PURCHASE_ORDER_STATUSES } from '../src/lib/procurement';

const TODAY = new Date('2026-10-07T00:00:00Z');

describe('OEM delivery risk indicator', () => {
  it('is green when already delivered on time', () => {
    const r = deliveryRisk({ expectedDate: '2026-10-05', requiredDate: '2026-10-10', receivedDate: '2026-10-05', today: TODAY });
    expect(r.color).toBe('green');
  });

  it('is red when delivered after the required date', () => {
    const r = deliveryRisk({ expectedDate: '2026-10-05', requiredDate: '2026-10-03', receivedDate: '2026-10-05', today: TODAY });
    expect(r.color).toBe('red');
  });

  it('is red when the expected delivery is already overdue', () => {
    const r = deliveryRisk({ expectedDate: '2026-10-01', requiredDate: '2026-10-20', today: TODAY });
    expect(r.color).toBe('red');
    expect(r.label).toMatch(/overdue/i);
  });

  it('is red when the OEM will miss the customer required date', () => {
    const r = deliveryRisk({ expectedDate: '2026-10-25', requiredDate: '2026-10-20', today: TODAY });
    expect(r.color).toBe('red');
    expect(r.label).toMatch(/miss customer required date/i);
  });

  it('is yellow when the expected delivery is tight against the required date', () => {
    const r = deliveryRisk({ expectedDate: '2026-10-14', requiredDate: '2026-10-20', today: TODAY });
    expect(r.color).toBe('yellow');
  });

  it('is yellow when there is no expected delivery date', () => {
    const r = deliveryRisk({ expectedDate: null, requiredDate: '2026-10-20', today: TODAY });
    expect(r.color).toBe('yellow');
    expect(r.label).toMatch(/no expected delivery date/i);
  });

  it('is green when on track', () => {
    const r = deliveryRisk({ expectedDate: '2026-10-30', requiredDate: '2026-11-15', today: TODAY });
    expect(r.color).toBe('green');
  });
});

describe('procurement helpers', () => {
  it('marks ready for dispatch only when received and PDI passed', () => {
    expect(isReadyForDispatch(true, true)).toBe(true);
    expect(isReadyForDispatch(true, false)).toBe(false);
    expect(isReadyForDispatch(false, true)).toBe(false);
  });

  it('labels purchase order statuses', () => {
    expect(labelFor(PURCHASE_ORDER_STATUSES, 'pending_approval')).toBe('Pending Approval');
    expect(labelFor(PURCHASE_ORDER_STATUSES, 'partially_received')).toBe('Partially Received');
  });
});
