import Link from 'next/link';
import { createProduct } from '../actions';
import { createClient } from '@/lib/supabase/server';

export const dynamic = 'force-dynamic';

export default async function ProductsPage({
  searchParams,
}: {
  searchParams: { error?: string; ok?: string };
}) {
  const supabase = createClient();
  const { data } = await supabase
    .from('products')
    .select('id, code, name, unit, category, hsn_code, status')
    .order('name');
  const rows = data ?? [];

  return (
    <>
      <div className="section-head">
        <div>
          <h1>Products</h1>
          <p className="subtitle">Item master used by tenders, quotations, procurement and dispatch.</p>
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
      {searchParams.ok && <div className="alert info">Product added.</div>}

      <div className="card">
        <h3>Add a product</h3>
        <form action={createProduct} className="stack">
          <div className="row">
            <div><label htmlFor="code">Code *</label><input id="code" name="code" required /></div>
            <div style={{ flex: '2 1 280px' }}><label htmlFor="name">Name *</label><input id="name" name="name" required /></div>
            <div><label htmlFor="unit">Unit</label><input id="unit" name="unit" defaultValue="NO" /></div>
          </div>
          <div className="row">
            <div><label htmlFor="category">Category</label><input id="category" name="category" /></div>
            <div><label htmlFor="hsn_code">HSN code</label><input id="hsn_code" name="hsn_code" /></div>
            <div><label htmlFor="manufacturer">Manufacturer</label><input id="manufacturer" name="manufacturer" /></div>
          </div>
          <div><label htmlFor="description">Description</label><input id="description" name="description" /></div>
          <button className="btn" type="submit">Add product</button>
        </form>
      </div>

      <div className="card">
        <h3>Existing products ({rows.length})</h3>
        {rows.length === 0 ? (
          <p className="empty">No products yet. Add one above, or run supabase/sample_data.sql.</p>
        ) : (
          <div style={{ overflowX: 'auto' }}>
            <table>
              <thead>
                <tr>
                  <th className="nowrap">Code</th>
                  <th>Name</th>
                  <th className="nowrap">Unit</th>
                  <th>Category</th>
                  <th className="nowrap">HSN</th>
                  <th className="nowrap">Status</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((r: any) => (
                  <tr key={r.id}>
                    <td className="nowrap">{r.code}</td>
                    <td>{r.name}</td>
                    <td className="nowrap">{r.unit}</td>
                    <td>{r.category ?? '—'}</td>
                    <td className="nowrap">{r.hsn_code ?? '—'}</td>
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
