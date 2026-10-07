import { describe, expect, it } from 'vitest';
import { canViewDashboard, monthlySales, oemPerformance } from '../src/lib/dashboard';

describe('management dashboard access', () => {
  it('is limited to management and administrators', () => {
    expect(canViewDashboard(['admin'])).toBe(true);
    expect(canViewDashboard(['management'])).toBe(true);
    expect(canViewDashboard(['sales'])).toBe(false);
    expect(canViewDashboard(['accounts', 'procurement'])).toBe(false);
    expect(canViewDashboard([])).toBe(false);
  });
});

describe('monthly sales aggregation', () => {
  it('groups order value by month, newest first', () => {
    const rows = monthlySales([
      { order_date: '2026-10-02', grand_total: 1000 },
      { order_date: '2026-10-20', grand_total: 500 },
      { order_date: '2026-09-15', grand_total: 800 },
    ]);
    expect(rows[0]).toEqual({ month: '2026-10', orders: 2, value: 1500 });
    expect(rows[1]).toEqual({ month: '2026-09', orders: 1, value: 800 });
  });
});

describe('OEM performance', () => {
  it('counts on-time, late, pending and at-risk per OEM', () => {
    const rows = oemPerformance([
      { oem_name: 'BEL', grand_total: 100, actual_delivery_date: '2026-10-01', risk: { color: 'green' } },
      { oem_name: 'BEL', grand_total: 200, actual_delivery_date: '2026-10-05', risk: { color: 'red' } },
      { oem_name: 'HAL', grand_total: 300, actual_delivery_date: null, risk: { color: 'red' } },
      { oem_name: 'HAL', grand_total: 150, actual_delivery_date: null, risk: { color: 'red' } },
    ]);
    const bel = rows.find((r) => r.oem === 'BEL')!;
    const hal = rows.find((r) => r.oem === 'HAL')!;
    expect(bel.onTime).toBe(1);
    expect(bel.late).toBe(1);
    expect(bel.pending).toBe(0);
    expect(hal.pending).toBe(2);
    expect(hal.atRisk).toBe(2);
    // worst (most late + at risk) comes first
    expect(rows[0].oem).toBe('HAL');
  });
});
