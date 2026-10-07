import Link from 'next/link';
import { listMaterialRequirements, listPurchaseOrders } from '@/lib/data';
import { deliveryRisk, labelFor, MATERIAL_REQUIREMENT_STATUSES, PURCHASE_ORDER_STATUSES, riskClass } from '@/lib/procurement';
import { formatDate, formatMoney } from '@/lib/format';

export const dynamic = 'force-dynamic';

export default async function ProcurementPage({ searchParams }: { searchParams: { error?: string } }) {
  const [requirements, orders] = await Promise.all([
    listMaterialRequirements({}),
    listPurchaseOrders({}),
  ]);

  const risky = orders.filter((o) => {
    const r = deliveryRisk({ expectedDate: o.expected_delivery_date, requiredDate: o.required_by_date, receivedDate: o.actual_delivery_date });
    return r.color === 'red' || r.color === 'yellow';
  });

  const counts = {
    requirementsOpen: requirements.filter((r) => !['received', 'cancelled'].includes(r.status)).length,
    awaitingApproval: orders.filter((o) => o.status === 'pending_approval').length,
    inDelivery: orders.filter((o) => ['approved', 'sent', 'partially_received'].includes(o.status)).length,
    atRisk: orders.filter((o) => deliveryRisk({ expectedDate: o.expected_delivery_date, requiredDate: o.required_by_date, receivedDate: o.actual_delivery_date }).color === 'red').length,
  };

  return (
    <>
      <div className="section-head">
        <div>
          <h1>Procurement</h1>
          <p className="subtitle">
            Customer order → material requirement → purchase request → OEM RFQ → OEM quotation →
            selection → approval → purchase order → delivery → receipt → PDI → ready for dispatch.
          </p>
        </div>
        <Link className="btn" href="/procurement/requirements/new">
          + New material requirement
        </Link>
      </div>

      {searchParams.error && <div className="alert error">{searchParams.error}</div>}

      <div className="grid3">
        <div className="card"><h3>Open requirements</h3><p style={{ fontSize: 26, margin: 0 }}>{counts.requirementsOpen}</p></div>
        <div className="card"><h3>POs awaiting approval</h3><p style={{ fontSize: 26, margin: 0 }}>{counts.awaitingApproval}</p></div>
        <div className="card"><h3>POs in delivery</h3><p style={{ fontSize: 26, margin: 0 }}>{counts.inDelivery}</p></div>
      </div>

      {counts.atRisk > 0 && (
        <div className="alert error">
          {counts.atRisk} purchase order(s) are at risk of delaying the customer delivery. See the red rows below.
        </div>
      )}

      <div className="card">
        <h3>Material requirements</h3>
        {requirements.length === 0 ? (
          <p className="empty">No material requirements yet.</p>
        ) : (
          <div style={{ overflowX: 'auto' }}>
            <table>
              <thead>
                <tr>
                  <th className="nowrap">Requirement</th>
                  <th className="nowrap">Customer order</th>
                  <th className="nowrap">Required by</th>
                  <th className="nowrap">Priority</th>
                  <th className="nowrap">Status</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                {requirements.map((r) => (
                  <tr key={r.id}>
                    <td className="nowrap"><Link href={`/procurement/requirements/${r.id}`}>{r.requirement_no}</Link></td>
                    <td className="nowrap">{r.customer_order_no ?? '—'}</td>
                    <td className="nowrap">{formatDate(r.required_by_date)}</td>
                    <td className="nowrap">{r.priority}</td>
                    <td className="nowrap"><span className="chip">{labelFor(MATERIAL_REQUIREMENT_STATUSES, r.status)}</span></td>
                    <td className="nowrap right"><Link className="btn small secondary" href={`/procurement/requirements/${r.id}`}>Open</Link></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      <div className="card">
        <h3>Purchase orders &amp; delivery risk</h3>
        {orders.length === 0 ? (
          <p className="empty">No purchase orders yet.</p>
        ) : (
          <div style={{ overflowX: 'auto' }}>
            <table>
              <thead>
                <tr>
                  <th className="nowrap">PO</th>
                  <th>OEM</th>
                  <th className="nowrap">Status</th>
                  <th className="nowrap">Expected</th>
                  <th className="nowrap">Actual</th>
                  <th className="nowrap">Required by</th>
                  <th className="nowrap">Risk</th>
                  <th className="nowrap">Value</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                {orders.map((o) => {
                  const risk = deliveryRisk({ expectedDate: o.expected_delivery_date, requiredDate: o.required_by_date, receivedDate: o.actual_delivery_date });
                  return (
                    <tr key={o.id}>
                      <td className="nowrap"><Link href={`/procurement/orders/${o.id}`}>{o.po_no}</Link></td>
                      <td>{o.oem_name}</td>
                      <td className="nowrap"><span className="chip">{labelFor(PURCHASE_ORDER_STATUSES, o.status)}</span></td>
                      <td className="nowrap">{formatDate(o.expected_delivery_date)}</td>
                      <td className="nowrap">{formatDate(o.actual_delivery_date)}</td>
                      <td className="nowrap">{formatDate(o.required_by_date)}</td>
                      <td className="nowrap"><span className={riskClass(risk.color)}>{risk.label}</span></td>
                      <td className="nowrap">{formatMoney(o.grand_total, o.currency)}</td>
                      <td className="nowrap right"><Link className="btn small secondary" href={`/procurement/orders/${o.id}`}>Open</Link></td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </>
  );
}
