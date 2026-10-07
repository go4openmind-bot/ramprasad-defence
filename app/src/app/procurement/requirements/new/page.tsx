import Link from 'next/link';
import { createMaterialRequirement } from '../../actions';
import { getUserDirectory, listCustomerOrderOptions } from '@/lib/data';

export const dynamic = 'force-dynamic';

export default async function NewMaterialRequirementPage({
  searchParams,
}: {
  searchParams: { error?: string; customer_order_id?: string };
}) {
  const [orders, users] = await Promise.all([listCustomerOrderOptions(), getUserDirectory()]);

  return (
    <>
      <h1>New material requirement</h1>
      <p className="subtitle">
        The demand to be procured. Record the date the material is required by — it drives the
        delivery-risk warnings against the customer order.
      </p>
      {searchParams.error && <div className="alert error">{searchParams.error}</div>}

      <form action={createMaterialRequirement} className="stack">
        <div className="card">
          <div className="row">
            <div>
              <label htmlFor="requirement_no">Requirement number</label>
              <input id="requirement_no" name="requirement_no" placeholder="Auto (MR-0001)" />
            </div>
            <div>
              <label htmlFor="customer_order_id">Customer order (optional)</label>
              <select id="customer_order_id" name="customer_order_id" defaultValue={searchParams.customer_order_id ?? ''}>
                <option value="">Not linked</option>
                {orders.map((o) => (
                  <option key={o.id} value={o.id}>
                    {o.order_no}
                  </option>
                ))}
              </select>
            </div>
          </div>
          <div className="row" style={{ marginTop: 12 }}>
            <div>
              <label htmlFor="required_by_date">Required by</label>
              <input id="required_by_date" name="required_by_date" type="date" />
            </div>
            <div>
              <label htmlFor="priority">Priority</label>
              <select id="priority" name="priority" defaultValue="medium">
                <option value="low">Low</option>
                <option value="medium">Medium</option>
                <option value="high">High</option>
                <option value="critical">Critical</option>
              </select>
            </div>
            <div>
              <label htmlFor="requested_by">Requested by</label>
              <select id="requested_by" name="requested_by" defaultValue="">
                <option value="">—</option>
                {users.map((u) => (
                  <option key={u.id} value={u.id}>
                    {u.full_name}
                  </option>
                ))}
              </select>
            </div>
          </div>
          <div style={{ marginTop: 12 }}>
            <label htmlFor="notes">Notes</label>
            <textarea id="notes" name="notes" />
          </div>
        </div>
        <div className="row tight">
          <button className="btn" type="submit">Create requirement</button>
          <Link className="btn secondary" href="/procurement">Cancel</Link>
        </div>
      </form>
    </>
  );
}
