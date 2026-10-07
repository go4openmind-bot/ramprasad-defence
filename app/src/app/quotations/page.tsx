import Link from 'next/link';
import { listQuotations, listCustomers } from '@/lib/data';
import { QUOTATION_STATUSES, quotationStatusClass, quotationStatusLabel } from '@/lib/quotation';
import { formatDate, formatMoney } from '@/lib/format';

export const dynamic = 'force-dynamic';

interface SearchParams {
  q?: string;
  status?: string;
  customer?: string;
  error?: string;
}

export default async function QuotationsPage({ searchParams }: { searchParams: SearchParams }) {
  const [rows, customers] = await Promise.all([
    listQuotations({ q: searchParams.q, status: searchParams.status, customer: searchParams.customer }),
    listCustomers(),
  ]);

  return (
    <>
      <div className="section-head">
        <div>
          <h1>Quotations</h1>
          <p className="subtitle">{rows.length} quotation(s) shown. An approved quotation is never edited — a revision is created instead.</p>
        </div>
        <Link className="btn" href="/quotations/new">
          + New quotation
        </Link>
      </div>

      {searchParams.error && <div className="alert error">{searchParams.error}</div>}

      <div className="card">
        <form className="toolbar" method="get" action="/quotations">
          <div style={{ flex: '1 1 240px' }}>
            <label htmlFor="q">Search</label>
            <input id="q" name="q" defaultValue={searchParams.q ?? ''} placeholder="Quotation number" />
          </div>
          <div>
            <label htmlFor="customer">Customer</label>
            <select id="customer" name="customer" defaultValue={searchParams.customer ?? ''}>
              <option value="">All customers</option>
              {customers.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name}
                </option>
              ))}
            </select>
          </div>
          <div>
            <label htmlFor="status">Status</label>
            <select id="status" name="status" defaultValue={searchParams.status ?? ''}>
              <option value="">All statuses</option>
              {QUOTATION_STATUSES.map((s) => (
                <option key={s.code} value={s.code}>
                  {s.label}
                </option>
              ))}
            </select>
          </div>
          <button className="btn" type="submit">
            Apply
          </button>
          <Link className="btn secondary" href="/quotations">
            Reset
          </Link>
        </form>
      </div>

      <div className="card">
        {rows.length === 0 ? (
          <p className="empty">No quotations match these filters.</p>
        ) : (
          <div style={{ overflowX: 'auto' }}>
            <table>
              <thead>
                <tr>
                  <th className="nowrap">Quotation</th>
                  <th>Customer</th>
                  <th className="nowrap">Tender</th>
                  <th className="nowrap">Status</th>
                  <th className="nowrap">Grand total</th>
                  <th className="nowrap">Margin</th>
                  <th className="nowrap">Valid until</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                {rows.map((r) => (
                  <tr key={r.id}>
                    <td className="nowrap">
                      <Link href={`/quotations/${r.id}`}>
                        {r.quotation_no} <span className="chip">v{r.version}</span>
                      </Link>
                    </td>
                    <td>{r.customer_name}</td>
                    <td className="nowrap">{r.tender_no ?? '—'}</td>
                    <td className="nowrap">
                      <span className={quotationStatusClass(r.status)}>{quotationStatusLabel(r.status)}</span>
                    </td>
                    <td className="nowrap">{formatMoney(r.grand_total, r.currency)}</td>
                    <td className="nowrap">{formatMoney(r.total_margin, r.currency)}</td>
                    <td className="nowrap">{formatDate(r.validity_date)}</td>
                    <td className="nowrap right">
                      <a className="btn small secondary" href={`/quotations/${r.id}/pdf`}>
                        PDF
                      </a>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </>
  );
}
