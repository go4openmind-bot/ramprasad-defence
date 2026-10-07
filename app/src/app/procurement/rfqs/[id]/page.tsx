import Link from 'next/link';
import { recordOemQuotation } from '../../actions';
import { getOemQuotationItems, getOemQuotationsForRfq, getOemRfq, getOemRfqItems } from '@/lib/data';
import { labelFor, OEM_QUOTATION_STATUSES, RFQ_STATUSES } from '@/lib/procurement';
import { formatDate, formatMoney } from '@/lib/format';

export const dynamic = 'force-dynamic';

export default async function OemRfqPage({
  params,
  searchParams,
}: {
  params: { id: string };
  searchParams: { error?: string };
}) {
  const rfq = await getOemRfq(params.id);
  if (!rfq) {
    return (
      <>
        <h1>RFQ not found</h1>
        <Link href="/procurement">← Back to procurement</Link>
      </>
    );
  }

  const [items, quotations] = await Promise.all([
    getOemRfqItems(params.id),
    getOemQuotationsForRfq(params.id),
  ]);
  const quoteTotals = await Promise.all(
    quotations.map(async (q) => ({ id: q.id, lines: (await getOemQuotationItems(q.id)).length })),
  );
  const lineCount = new Map(quoteTotals.map((q) => [q.id, q.lines]));
  const today = new Date().toISOString().slice(0, 10);

  return (
    <>
      {searchParams.error && <div className="alert error">{searchParams.error}</div>}

      <div className="section-head">
        <div>
          <h1>RFQ {rfq.rfq_no}</h1>
          <p className="subtitle">
            OEM: {rfq.oem_name} · <span className="chip">{labelFor(RFQ_STATUSES, rfq.status)}</span> · due{' '}
            {formatDate(rfq.due_date)}
          </p>
        </div>
        {rfq.material_requirement_id && (
          <Link className="btn secondary" href={`/procurement/requirements/${rfq.material_requirement_id}`}>
            ← Requirement
          </Link>
        )}
      </div>

      <div className="card">
        <h3>RFQ lines</h3>
        <table>
          <thead>
            <tr>
              <th className="nowrap">#</th>
              <th>Description</th>
              <th className="nowrap">Qty</th>
              <th className="nowrap">Unit</th>
            </tr>
          </thead>
          <tbody>
            {items.map((i) => (
              <tr key={i.id}>
                <td className="nowrap">{i.line_no}</td>
                <td>{i.description}</td>
                <td className="nowrap">{i.quantity}</td>
                <td className="nowrap">{i.unit}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <div className="card">
        <h3>OEM quotations received</h3>
        {quotations.length === 0 ? (
          <p className="muted small">No quotations recorded yet.</p>
        ) : (
          <ul className="list">
            {quotations.map((q) => (
              <li key={q.id}>
                <Link href={`/procurement/quotations/${q.id}`}>{q.quotation_no}</Link>{' '}
                <span className="chip">{labelFor(OEM_QUOTATION_STATUSES, q.status)}</span>
                <div className="hint">
                  {lineCount.get(q.id) ?? 0} line(s) · {formatMoney(q.grand_total, q.currency)} · lead{' '}
                  {q.lead_time_days ?? '—'} day(s)
                </div>
              </li>
            ))}
          </ul>
        )}
      </div>

      <div className="card">
        <h3>Record an OEM quotation</h3>
        <form action={recordOemQuotation} className="stack">
          <input type="hidden" name="oem_rfq_id" value={rfq.id} />
          <input type="hidden" name="oem_id" value={rfq.oem_id} />
          <div className="row">
            <div>
              <label htmlFor="quote_date">Quote date *</label>
              <input id="quote_date" name="quote_date" type="date" defaultValue={today} required />
            </div>
            <div>
              <label htmlFor="validity_date">Valid until</label>
              <input id="validity_date" name="validity_date" type="date" />
            </div>
            <div>
              <label htmlFor="lead_time_days">Lead time (days)</label>
              <input id="lead_time_days" name="lead_time_days" type="number" min="0" step="1" />
            </div>
            <div>
              <label htmlFor="currency">Currency</label>
              <input id="currency" name="currency" defaultValue="INR" />
            </div>
          </div>
          <div className="row" style={{ marginTop: 12 }}>
            <div>
              <label htmlFor="payment_terms">Payment terms</label>
              <input id="payment_terms" name="payment_terms" />
            </div>
            <div>
              <label htmlFor="delivery_terms">Delivery terms</label>
              <input id="delivery_terms" name="delivery_terms" />
            </div>
            <div>
              <label htmlFor="warranty">Warranty</label>
              <input id="warranty" name="warranty" />
            </div>
          </div>

          <div style={{ marginTop: 12 }}>
            <label>Prices</label>
            <table>
              <thead>
                <tr>
                  <th className="nowrap">#</th>
                  <th>Description</th>
                  <th className="nowrap">Qty</th>
                  <th className="nowrap">Unit price *</th>
                  <th className="nowrap">GST %</th>
                </tr>
              </thead>
              <tbody>
                {items.map((i) => (
                  <tr key={i.id}>
                    <td className="nowrap">{i.line_no}</td>
                    <td>{i.description}</td>
                    <td className="nowrap">{i.quantity} {i.unit}</td>
                    <td><input name={`price_${i.id}`} type="number" min="0" step="0.01" required /></td>
                    <td><input name={`tax_${i.id}`} type="number" min="0" max="100" step="0.01" defaultValue="18" /></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          <div>
            <label htmlFor="notes">Notes</label>
            <textarea id="notes" name="notes" />
          </div>
          <button className="btn" type="submit">Save quotation</button>
        </form>
      </div>
    </>
  );
}
