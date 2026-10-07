import Link from 'next/link';
import { createQuotation, updateQuotationHeader } from '@/app/quotations/actions';
import { QUOTATION_STATUSES } from '@/lib/quotation';
import type { Customer, Quotation } from '@/lib/types';

export interface QuotationFormProps {
  mode: 'create' | 'edit';
  quotation?: Quotation;
  customers: Customer[];
  tenders: { id: string; tender_no: string; title: string }[];
  error?: string;
  defaultTenderId?: string;
  defaultCustomerId?: string;
}

export function QuotationForm({
  mode,
  quotation,
  customers,
  tenders,
  error,
  defaultTenderId,
  defaultCustomerId,
}: QuotationFormProps) {
  const action = mode === 'create' ? createQuotation : updateQuotationHeader;
  const today = new Date().toISOString().slice(0, 10);

  return (
    <form action={action} className="stack">
      {error && <div className="alert error">{error}</div>}
      {mode === 'edit' && quotation && <input type="hidden" name="id" value={quotation.id} />}

      <div className="card">
        <h2>Parties</h2>
        <div className="row">
          <div>
            <label htmlFor="customer_id">Customer *</label>
            <select
              id="customer_id"
              name="customer_id"
              defaultValue={quotation?.customer_id ?? defaultCustomerId ?? ''}
              required
            >
              <option value="">Select a customer…</option>
              {customers.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name}
                </option>
              ))}
            </select>
          </div>
          <div>
            <label htmlFor="tender_id">Tender (optional)</label>
            <select id="tender_id" name="tender_id" defaultValue={quotation?.tender_id ?? defaultTenderId ?? ''}>
              <option value="">Not linked</option>
              {tenders.map((t) => (
                <option key={t.id} value={t.id}>
                  {t.tender_no} — {t.title}
                </option>
              ))}
            </select>
          </div>
        </div>
      </div>

      <div className="card">
        <h2>Dates and terms</h2>
        <div className="row">
          <div>
            <label htmlFor="quote_date">Quote date *</label>
            <input
              id="quote_date"
              name="quote_date"
              type="date"
              defaultValue={quotation?.quote_date ?? today}
              required
            />
          </div>
          <div>
            <label htmlFor="validity_date">Quotation validity (valid until)</label>
            <input
              id="validity_date"
              name="validity_date"
              type="date"
              defaultValue={quotation?.validity_date ?? ''}
            />
          </div>
          <div>
            <label htmlFor="currency">Currency</label>
            <input id="currency" name="currency" defaultValue={quotation?.currency ?? 'INR'} />
          </div>
        </div>

        <div className="row" style={{ marginTop: 12 }}>
          <div>
            <label htmlFor="payment_terms">Payment terms</label>
            <input
              id="payment_terms"
              name="payment_terms"
              defaultValue={quotation?.payment_terms ?? ''}
              placeholder="e.g. 30% advance, 70% on delivery"
            />
          </div>
          <div>
            <label htmlFor="delivery_terms">Delivery terms</label>
            <input
              id="delivery_terms"
              name="delivery_terms"
              defaultValue={quotation?.delivery_terms ?? ''}
              placeholder="e.g. 8–10 weeks, FOR destination"
            />
          </div>
        </div>

        <div style={{ marginTop: 12 }}>
          <label htmlFor="warranty">Warranty</label>
          <input
            id="warranty"
            name="warranty"
            defaultValue={quotation?.warranty ?? ''}
            placeholder="e.g. 24 months from delivery"
          />
        </div>

        <div style={{ marginTop: 12 }}>
          <label htmlFor="notes">Notes / terms &amp; conditions</label>
          <textarea id="notes" name="notes" defaultValue={quotation?.notes ?? ''} />
        </div>

        {mode === 'edit' && quotation && (
          <div style={{ marginTop: 12 }}>
            <label htmlFor="status">Status</label>
            <select id="status" name="status" defaultValue={quotation.status}>
              {QUOTATION_STATUSES.map((s) => (
                <option key={s.code} value={s.code}>
                  {s.label}
                </option>
              ))}
            </select>
          </div>
        )}
      </div>

      <div className="row tight">
        <button className="btn" type="submit">
          {mode === 'create' ? 'Create quotation' : 'Save header'}
        </button>
        <Link
          className="btn secondary"
          href={mode === 'edit' && quotation ? `/quotations/${quotation.id}` : '/quotations'}
        >
          Cancel
        </Link>
      </div>
    </form>
  );
}
