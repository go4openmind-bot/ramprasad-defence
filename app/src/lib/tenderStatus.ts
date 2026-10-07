/**
 * The tender status pipeline. Single source of truth for the module.
 * Codes match public.tenders.status in the database (migration 0014).
 */

export const TENDER_STATUSES = [
  { code: 'new', label: 'New' },
  { code: 'under_review', label: 'Under Review' },
  { code: 'qualified', label: 'Qualified' },
  { code: 'requirement_analysis', label: 'Requirement Analysis' },
  { code: 'oem_pricing', label: 'OEM Pricing' },
  { code: 'quotation_preparation', label: 'Quotation Preparation' },
  { code: 'approval_pending', label: 'Approval Pending' },
  { code: 'submitted', label: 'Submitted' },
  { code: 'technical_evaluation', label: 'Technical Evaluation' },
  { code: 'commercial_evaluation', label: 'Commercial Evaluation' },
  { code: 'won', label: 'Won' },
  { code: 'lost', label: 'Lost' },
  { code: 'cancelled', label: 'Cancelled' },
] as const;

export type TenderStatus = (typeof TENDER_STATUSES)[number]['code'];

export const TENDER_STATUS_CODES = TENDER_STATUSES.map((s) => s.code) as TenderStatus[];

const LABELS: Record<string, string> = Object.fromEntries(
  TENDER_STATUSES.map((s) => [s.code, s.label]),
);

/** Human label for a status code; returns the raw code if unknown. */
export function statusLabel(code: string | null | undefined): string {
  if (!code) return '—';
  return LABELS[code] ?? code;
}

/** Position in the pipeline (0-based). Unknown codes sort last. */
export function statusIndex(code: string | null | undefined): number {
  if (!code) return -1;
  const i = TENDER_STATUS_CODES.indexOf(code as TenderStatus);
  return i === -1 ? TENDER_STATUS_CODES.length : i;
}

/** Stages where the tender is finished. */
export const TERMINAL_STATUSES: TenderStatus[] = ['won', 'lost', 'cancelled'];

export function isTerminal(code: string | null | undefined): boolean {
  return !!code && TERMINAL_STATUSES.includes(code as TenderStatus);
}

/** CSS class for the status pill. */
export function statusClass(code: string | null | undefined): string {
  if (code === 'won') return 'status-pill status-won';
  if (code === 'lost' || code === 'cancelled') return 'status-pill status-lost';
  if (code === 'approval_pending' || code === 'technical_evaluation' || code === 'commercial_evaluation')
    return 'status-pill status-pending';
  return 'status-pill status-active';
}

/** Normalise any external input to a valid status code. */
export function parseStatus(value: unknown): TenderStatus {
  return TENDER_STATUS_CODES.includes(value as TenderStatus)
    ? (value as TenderStatus)
    : 'new';
}
