import Link from 'next/link';
import { createCustomer } from '../actions';
import { createClient } from '@/lib/supabase/server';

export const dynamic = 'force-dynamic';

export default async function CustomersPage({
  searchParams,
}: {
  searchParams: { error?: string; ok?: string };
}) {
  const supabase = createClient();
  const { data } = await supabase
    .from('customers')
    .select('id, code, name, customer_type, city, state, status')
    .order('name');
  const rows = data ?? [];

  return (
    <>
      <div className="section-head">
        <div>
          <h1>Customers</h1>
          <p className="subtitle">Master list of defence customers / buyers.</p>
        </div>
      </div>

      <Nav />

      {searchParams.error && <div className="alert error">{searchParams.error}</div>}
      {searchParams.ok && <div className="alert info">Customer added.</div>}

      <div className="card">
        <h3>Add a customer</h3>
        <form action={createCustomer} className="stack">
          <div className="row">
            <div><label htmlFor="code">Code *</label><input id="code" name="code" required /></div>
            <div style={{ flex: '2 1 280px' }}><label htmlFor="name">Name *</label><input id="name" name="name" required /></div>
            <div>
              <label htmlFor="customer_type">Type</label>
              <select id="customer_type" name="customer_type" defaultValue="mod">
                <option value="mod">MoD</option>
                <option value="dpsu">DPSU</option>
                <option value="armed_forces">Armed forces</option>
                <option value="paramilitary">Paramilitary</option>
                <option value="ordnance_factory">Ordnance factory</option>
                <option value="police">Police</option>
                <option value="government_other">Government (other)</option>
                <option value="private">Private</option>
                <option value="other">Other</option>
              </select>
            </div>
          </div>
          <div className="row">
            <div><label htmlFor="city">City</label><input id="city" name="city" /></div>
            <div><label htmlFor="state">State</label><input id="state" name="state" /></div>
            <div><label htmlFor="pincode">Pincode</label><input id="pincode" name="pincode" /></div>
          </div>
          <div className="row">
            <div><label htmlFor="gstin">GSTIN</label><input id="gstin" name="gstin" /></div>
            <div><label htmlFor="email">Email</label><input id="email" name="email" type="email" /></div>
            <div><label htmlFor="phone">Phone</label><input id="phone" name="phone" /></div>
          </div>
          <button className="btn" type="submit">Add customer</button>
        </form>
      </div>

      <div className="card">
        <h3>Existing customers ({rows.length})</h3>
        {rows.length === 0 ? (
          <p className="empty">No customers yet. Add one above, or run supabase/sample_data.sql.</p>
        ) : (
          <div style={{ overflowX: 'auto' }}>
            <table>
              <thead>
                <tr>
                  <th className="nowrap">Code</th>
                  <th>Name</th>
                  <th className="nowrap">Type</th>
                  <th>City</th>
                  <th className="nowrap">Status</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((r: any) => (
                  <tr key={r.id}>
                    <td className="nowrap">{r.code}</td>
                    <td>{r.name}</td>
                    <td className="nowrap">{r.customer_type}</td>
                    <td>{r.city ?? '—'}</td>
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

function Nav() {
  return (
    <div className="card">
      <div className="row tight">
        <Link className="btn small secondary" href="/masters/customers">Customers</Link>
        <Link className="btn small secondary" href="/masters/products">Products</Link>
        <Link className="btn small secondary" href="/masters/oems">OEMs</Link>
      </div>
    </div>
  );
}
