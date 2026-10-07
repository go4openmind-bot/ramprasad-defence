/**
 * Quotation helpers. Status codes and compliance values match the database
 * (migration 0007 + 0015).
 */

export const QUOTATION_STATUSES = [
  { code: 'draft', label: 'Draft' },
  { code: 'pending_approval', label: 'Pending Approval' },
  { code: 'approved', label: 'Approved' },
  { code: 'rejected', label: 'Rejected' },
  { code: 'submitted', label: 'Submitted' },
  { code: 'revised', label: 'Revised' },
  { code: 'won', label: 'Won' },
  { code: 'lost', label: 'Lost' },
  { code: 'expired', label: 'Expired' },
] as const;

export type QuotationStatus = (typeof QUOTATION_STATUSES)[number]['code'];
export const QUOTATION_STATUS_CODES = QUOTATION_STATUSES.map((s) => s.code);

/** Statuses after which the quotation content is frozen (a revision is required). */
export const FROZEN_QUOTATION_STATUSES: QuotationStatus[] = ['approved', 'submitted', 'won', 'lost'];

export function quotationStatusLabel(code: string | null | undefined): string {
  if (!code) return '—';
  return QUOTATION_STATUSES.find((s) => s.code === code)?.label ?? code;
}

export function quotationStatusClass(code: string | null | undefined): string {
  if (code === 'won' || code === 'approved') return 'status-pill status-won';
  if (code === 'lost' || code === 'rejected' || code === 'expired') return 'status-pill status-lost';
  if (code === 'pending_approval' || code === 'submitted' || code === 'revised')
    return 'status-pill status-pending';
  return 'status-pill status-active';
}

export function isFrozen(code: string | null | undefined): boolean {
  return !!code && FROZEN_QUOTATION_STATUSES.includes(code as QuotationStatus);
}

export function parseQuotationStatus(value: unknown): QuotationStatus {
  return QUOTATION_STATUS_CODES.includes(value as QuotationStatus)
    ? (value as QuotationStatus)
    : 'draft';
}

export const COMPLIANCE_VALUES = [
  { code: 'compliant', label: 'Compliant' },
  { code: 'partially_compliant', label: 'Partially compliant' },
  { code: 'non_compliant', label: 'Non-compliant' },
  { code: 'pending', label: 'Pending' },
  { code: 'not_applicable', label: 'Not applicable' },
] as const;

const COMPLIANCE_SEVERITY: Record<string, number> = {
  compliant: 0,
  not_applicable: 1,
  pending: 2,
  partially_compliant: 3,
  non_compliant: 4,
};

export function complianceLabel(code: string | null | undefined): string {
  if (!code) return '—';
  return COMPLIANCE_VALUES.find((c) => c.code === code)?.label ?? code;
}

export function complianceClass(code: string | null | undefined): string {
  switch (code) {
    case 'compliant':
      return 'badge green';
    case 'partially_compliant':
      return 'badge yellow';
    case 'non_compliant':
      return 'badge red';
    case 'pending':
      return 'badge grey';
    default:
      return 'badge grey';
  }
}

/**
 * Overall technical compliance for a quotation: the worst compliance value
 * across its lines. Empty list => 'pending'.
 */
export function complianceRollup(items: { technical_compliance: string }[]): string {
  if (!items.length) return 'pending';
  let worst = 'compliant';
  for (const it of items) {
    const sev = COMPLIANCE_SEVERITY[it.technical_compliance] ?? 2;
    if (sev >= (COMPLIANCE_SEVERITY[worst] ?? 0)) worst = it.technical_compliance;
  }
  return worst;
}

/** Margin as a percentage of net selling. Null when there is no selling value. */
export function marginPercent(base: number, margin: number): number | null {
  if (!base || base <= 0) return null;
  return Math.round((margin / base) * 10000) / 100;
}
