import Link from 'next/link';
import { selectOemQuotation } from '../../actions';
import { getOemQuotation, getOemQuotationItems } from '@/lib/data';
import { labelFor, OEM_QUOTATION_STATUSES } from '@/lib/procurement';
import { formatDate, formatMoney } from '@/lib/format';

export const dynamic = 'force-dynamic';

export default async function OemQuotationPage({
  params,
  searchParams,
}: {
  params: { id: string };
  searchParams: { error?: string };
}) {
  const quote = await getOemQuotation(params.id);
  if (!quote) {
    return (
      <>
        <h1>OEM quotation not found</h1>
        <Link href="/procurement">← Back to procurement</Link>
      </>
    );
  }
  const items = await getOemQuotationItems(params.id);

  return (
    <>
      {searchParams.error && <div className="alert error">{searchParams.error}</div>}

      <div className="section-head">
        <div>
          <h1>{quote.quotation_no}</h1>
          <p className="subtitle">
            {quote.oem_name} · <span className="chip">{labelFor(OEM_QUOTATION_STATUSES, quote.status)}</span> ·
            quoted {formatDate(quote.quote_date)}
          </p>
        </div>
        {quote.oem_rfq_id && (
          <Link className="btn secondary" href={`/procurement/rfqs/${quote.oem_rfq_id}`}>← RFQ</Link>
        )}
      </div>

      <div className="grid2">
        <div className="card">
          <h3>Terms</h3>
          <dl className="kv">
            <dt>Payment</dt><dd>{quote.payment_terms ?? '—'}</dd>
            <dt>Delivery</dt><dd>{quote.delivery_terms ?? '—'}</dd>
            <dt>Warranty</dt><dd>{quote.warranty ?? '—'}</dd>
            <dt>Lead time</dt><dd>{quote.lead_time_days ?? '—'} day(s)</dd>
            <dt>Valid until</dt><dd>{formatDate(quote.validity_date)}</dd>
          </dl>
        </div>
        <div className="card">
          <h3>Totals</h3>
          <dl className="kv">
            <dt>Net (ex-tax)</dt><dd>{formatMoney(quote.subtotal, quote.currency)}</dd>
            <dt>GST</dt><dd>{formatMoney(quote.tax_total, quote.currency)}</dd>
            <dt><strong>Grand total</strong></dt><dd><strong>{formatMoney(quote.grand_total, quote.currency)}</strong></dd>
          </dl>
        </div>
      </div>

      <div className="card">
        <h3>Quoted lines</h3>
        <table>
          <thead>
            <tr>
              <th className="nowrap">#</th>
              <th>Description</th>
              <th className="nowrap">Qty</th>
              <th className="nowrap">Unit price</th>
              <th className="nowrap">GST %</th>
              <th className="nowrap">Line total</th>
            </tr>
          </thead>
          <tbody>
            {items.map((i) => (
              <tr key={i.id}>
                <td className="nowrap">{i.line_no}</td>
                <td>{i.description}</td>
                <td className="nowrap">{i.quantity} {i.unit}</td>
                <td className="nowrap">{formatMoney(i.unit_price, quote.currency)}</td>
                <td className="nowrap">{i.tax_pct}</td>
                <td className="nowrap">{formatMoney(i.line_total, quote.currency)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {quote.status === 'received' ? (
        <form action={selectOemQuotation} className="card">
          <input type="hidden" name="quotation_id" value={quote.id} />
          <h3>Select this OEM</h3>
          <p className="muted small">
            This marks the quotation selected, rejects the other quotes for the same RFQ, and creates a
            purchase order in <strong>pending approval</strong>.
          </p>
          <button className="btn" type="submit">Select OEM &amp; create purchase order</button>
        </form>
      ) : (
        <div className="alert info">
          This quotation is <strong>{labelFor(OEM_QUOTATION_STATUSES, quote.status)}</strong>.
        </div>
      )}
    </>
  );
}
