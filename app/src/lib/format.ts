/** Small formatting helpers (no external dependency). */

export function formatDate(value: string | null | undefined): string {
  if (!value) return '—';
  const d = new Date(value.length <= 10 ? `${value}T00:00:00Z` : value);
  if (Number.isNaN(d.getTime())) return value;
  return d.toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric', timeZone: 'UTC' });
}

export function formatDateTime(value: string | null | undefined): string {
  if (!value) return '—';
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return value;
  return d.toLocaleString('en-IN', { day: '2-digit', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' });
}

export function formatMoney(value: number | null | undefined, currency = 'INR'): string {
  if (value === null || value === undefined) return '—';
  const symbol = currency === 'INR' ? '₹' : `${currency} `;
  return `${symbol}${Number(value).toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}

export function priorityLabel(p: string | null | undefined): string {
  if (!p) return '—';
  return p.charAt(0).toUpperCase() + p.slice(1);
}
