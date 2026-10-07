/**
 * Procurement helpers: stage statuses and the automatic OEM-delivery risk
 * indicator. Pure functions so the risk rules can be unit-tested with a fixed
 * "today".
 */

export const DELIVERY_RISK_WARNING_DAYS = 7;

export const MATERIAL_REQUIREMENT_STATUSES = [
  { code: 'open', label: 'Open' },
  { code: 'sourcing', label: 'Sourcing' },
  { code: 'rfq_sent', label: 'RFQ Sent' },
  { code: 'quoted', label: 'Quoted' },
  { code: 'ordered', label: 'Ordered' },
  { code: 'partially_received', label: 'Partially Received' },
  { code: 'received', label: 'Received' },
  { code: 'cancelled', label: 'Cancelled' },
] as const;

export const RFQ_STATUSES = [
  { code: 'draft', label: 'Draft' },
  { code: 'sent', label: 'Sent' },
  { code: 'quotes_received', label: 'Quotes Received' },
  { code: 'closed', label: 'Closed' },
  { code: 'cancelled', label: 'Cancelled' },
] as const;

export const OEM_QUOTATION_STATUSES = [
  { code: 'received', label: 'Received' },
  { code: 'selected', label: 'Selected' },
  { code: 'rejected', label: 'Rejected' },
  { code: 'expired', label: 'Expired' },
] as const;

export const PURCHASE_ORDER_STATUSES = [
  { code: 'draft', label: 'Draft' },
  { code: 'pending_approval', label: 'Pending Approval' },
  { code: 'approved', label: 'Approved' },
  { code: 'sent', label: 'Sent' },
  { code: 'partially_received', label: 'Partially Received' },
  { code: 'received', label: 'Received' },
  { code: 'cancelled', label: 'Cancelled' },
  { code: 'closed', label: 'Closed' },
] as const;

export function labelFor(
  list: ReadonlyArray<{ code: string; label: string }>,
  code: string | null | undefined,
): string {
  if (!code) return '—';
  return list.find((s) => s.code === code)?.label ?? code;
}

export type RiskLevel = 'red' | 'yellow' | 'green' | 'grey';

export interface DeliveryRisk {
  level: RiskLevel;
  color: RiskLevel;
  label: string;
  daysToExpected: number | null;
}

function toUtcDate(value: string | Date | null | undefined): number | null {
  if (!value) return null;
  const d = value instanceof Date ? value : new Date(`${value}T00:00:00Z`);
  if (Number.isNaN(d.getTime())) return null;
  return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate());
}

function diffDays(a: number, b: number): number {
  return Math.round((a - b) / 86_400_000);
}

export interface DeliveryRiskInput {
  /** Expected delivery date on the purchase order. */
  expectedDate: string | Date | null | undefined;
  /** The date the material is required (customer order / material requirement). */
  requiredDate?: string | Date | null;
  /** Set once the material has actually been received. */
  receivedDate?: string | Date | null;
  today?: Date;
}

/**
 * Automatic risk indicator: does OEM delivery threaten the customer deadline?
 *   green  = on track (or already delivered)
 *   yellow = tight / unknown (within the warning window, or no expected date)
 *   red    = will miss the required date, or the expected date is already past
 */
export function deliveryRisk(input: DeliveryRiskInput): DeliveryRisk {
  const today = input.today ?? new Date();
  const t = toUtcDate(today);
  const expected = toUtcDate(input.expectedDate);
  const required = toUtcDate(input.requiredDate);
  const received = toUtcDate(input.receivedDate);

  if (received !== null) {
    if (required !== null && received > required) {
      return { level: 'red', color: 'red', label: 'Delivered late (after required date)', daysToExpected: expected !== null ? diffDays(expected, t!) : null };
    }
    return { level: 'green', color: 'green', label: 'Delivered', daysToExpected: expected !== null ? diffDays(expected, t!) : null };
  }

  if (expected === null) {
    return { level: 'yellow', color: 'yellow', label: 'No expected delivery date', daysToExpected: null };
  }

  const daysToExpected = diffDays(expected, t!);

  if (daysToExpected < 0) {
    return { level: 'red', color: 'red', label: `Expected delivery overdue by ${Math.abs(daysToExpected)} day(s)`, daysToExpected };
  }

  if (required !== null && expected > required) {
    const slip = diffDays(expected, required);
    return {
      level: 'red',
      color: 'red',
      label: `Will miss customer required date by ${slip} day(s)`,
      daysToExpected,
    };
  }

  if (required !== null && diffDays(required, expected) <= DELIVERY_RISK_WARNING_DAYS) {
    return {
      level: 'yellow',
      color: 'yellow',
      label: `Tight — expected within ${diffDays(required, expected)} day(s) of required date`,
      daysToExpected,
    };
  }

  return { level: 'green', color: 'green', label: 'On track', daysToExpected };
}

export function riskClass(color: RiskLevel): string {
  return `badge ${color}`;
}

/** "Ready for dispatch" = received and inspection passed. */
export function isReadyForDispatch(received: boolean, pdiPassed: boolean): boolean {
  return received && pdiPassed;
}
