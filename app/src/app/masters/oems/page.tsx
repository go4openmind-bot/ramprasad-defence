import Link from 'next/link';
import { createOem } from '../actions';
import { createClient } from '@/lib/supabase/server';

export const dynamic = 'force-dynamic';

export default async function OemsPage({
  searchParams,
}: {
  searchParams: { error?: string; ok?: string };
}) {
  const supabase = createClient();
  const { data } = await supabase
    .from('oems')
    .select('id, code, name, city, gstin, payment_terms, status')
    .order('name');
  const rows = data ?? [];

  return (
    <>
      <div className="section-head">
        <div>
          <h1>OEMs</h1>
          <p className="subtitle">OEM / supplier master used by procurement.</p>
        </div>
      </div>

      <div className="card">
        <div className="row tight">
          <Link className="btn small secondary" href="/masters/customers">Customers</Link>
          <Link className="btn small secondary" href="/masters/products">Products</Link>
          <Link className="btn small secondary" href="/masters/oems">OEMs</Link>
        </div>
      </div>

      {searchParams.error && <div className="alert error">{searchParams.error}</div>}
      {searchParams.ok && <div className="alert info">OEM added.</div>}

      <div className="card">
        <h3>Add an OEM</h3>
        <form action={createOem} className="stack">
          <div className="row">
            <div><label htmlFor="code">Code *</label><input id="code" name="code" required /></div>
            <div style={{ flex: '2 1 280px' }}><label htmlFor="name">Name *</label><input id="name" name="name" required /></div>
            <div><label htmlFor="oem_type">Type</label><input id="oem_type" name="oem_type" placeholder="PSU / Private" /></div>
          </div>
          <div className="row">
            <div><label htmlFor="city">City</label><input id="city" name="city" /></div>
            <div><label htmlFor="state">State</label><input id="state" name="state" /></div>
            <div><label htmlFor="gstin">GSTIN</label><input id="gstin" name="gstin" /></div>
          </div>
          <div className="row">
            <div><label htmlFor="email">Email</label><input id="email" name="email" type="email" /></div>
            <div><label htmlFor="phone">Phone</label><input id="phone" name="phone" /></div>
            <div><label htmlFor="payment_terms">Payment terms</label><input id="payment_terms" name="payment_terms" placeholder="e.g. 30% advance, 70% on delivery" /></div>
          </div>
          <button className="btn" type="submit">Add OEM</button>
        </form>
      </div>

      <div className="card">
        <h3>Existing OEMs ({rows.length})</h3>
        {rows.length === 0 ? (
          <p className="empty">No OEMs yet. Add one above, or run supabase/sample_data.sql.</p>
        ) : (
          <div style={{ overflowX: 'auto' }}>
            <table>
              <thead>
                <tr>
                  <th className="nowrap">Code</th>
                  <th>Name</th>
                  <th>City</th>
                  <th className="nowrap">GSTIN</th>
                  <th>Payment terms</th>
                  <th className="nowrap">Status</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((r: any) => (
                  <tr key={r.id}>
                    <td className="nowrap">{r.code}</td>
                    <td>{r.name}</td>
                    <td>{r.city ?? '—'}</td>
                    <td className="nowrap">{r.gstin ?? '—'}</td>
                    <td>{r.payment_terms ?? '—'}</td>
                    <td className="nowrap">{r.status}</td>
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
