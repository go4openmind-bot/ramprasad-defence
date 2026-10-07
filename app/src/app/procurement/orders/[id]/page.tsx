import Link from 'next/link';
import {
  createPdi,
  decidePurchaseOrder,
  recordMaterialReceipt,
  setExpectedDelivery,
  uploadProcurementDocument,
} from '../../actions';
import {
  getCurrentContext,
  getMaterialReceipts,
  getPdiRecordsForReceipts,
  getProcurementDocuments,
  getPurchaseApprovals,
  getPurchaseOrder,
  getPurchaseOrderItems,
  getUserDirectory,
} from '@/lib/data';
import {
  deliveryRisk,
  isReadyForDispatch,
  labelFor,
  PURCHASE_ORDER_STATUSES,
  riskClass,
} from '@/lib/procurement';
import { formatDate, formatDateTime, formatMoney } from '@/lib/format';

export const dynamic = 'force-dynamic';

export default async function PurchaseOrderPage({
  params,
  searchParams,
}: {
  params: { id: string };
  searchParams: { error?: string };
}) {
  const po = await getPurchaseOrder(params.id);
  if (!po) {
    return (
      <>
        <h1>Purchase order not found</h1>
        <Link href="/procurement">← Back to procurement</Link>
      </>
    );
  }

  const [items, approvals, receipts, documents, users, me] = await Promise.all([
    getPurchaseOrderItems(params.id),
    getPurchaseApprovals(params.id),
    getMaterialReceipts(params.id),
    getProcurementDocuments('purchase_order', params.id),
    getUserDirectory(),
    getCurrentContext(),
  ]);
  const pdis = await getPdiRecordsForReceipts(receipts.map((r) => r.id));

  const names = new Map(users.map((u) => [u.id, u.full_name]));
  const canApprove = !!me && (me.roles.includes('admin') || me.roles.includes('management'));
  const risk = deliveryRisk({
    expectedDate: po.expected_delivery_date,
    requiredDate: po.required_by_date,
    receivedDate: po.actual_delivery_date,
  });
  const anyReceived = receipts.some((r) => ['received', 'partial'].includes(r.status));
  const anyPdiPass = pdis.some((p) => p.result === 'pass');
  const ready = isReadyForDispatch(anyReceived, anyPdiPass);
  const today = new Date().toISOString().slice(0, 10);

  return (
    <>
      {searchParams.error && <div className="alert error">{searchParams.error}</div>}

      <div className="section-head">
        <div>
          <h1>PO {po.po_no}</h1>
          <p className="subtitle">
            {po.oem_name} · <span className="chip">{labelFor(PURCHASE_ORDER_STATUSES, po.status)}</span> ·{' '}
            <span className={riskClass(risk.color)}>{risk.label}</span>
          </p>
        </div>
        <Link className="btn secondary" href="/procurement">← Procurement</Link>
      </div>

      {risk.color === 'red' && (
        <div className="alert error">
          Risk: this OEM delivery may delay the customer delivery. Required by{' '}
          {formatDate(po.required_by_date)}, expected {formatDate(po.expected_delivery_date)}.
        </div>
      )}

      <div className="grid2">
        <div className="card">
          <h3>Delivery &amp; terms</h3>
          <dl className="kv">
            <dt>OEM</dt><dd>{po.oem_name}</dd>
            <dt>Customer order</dt><dd>{po.customer_order_no ?? '—'}</dd>
            <dt>Requirement</dt><dd>{po.requirement_no ?? '—'}</dd>
            <dt>Expected delivery</dt><dd>{formatDate(po.expected_delivery_date)}</dd>
            <dt>Actual delivery</dt><dd>{formatDate(po.actual_delivery_date)}</dd>
            <dt>Required by</dt><dd>{formatDate(po.required_by_date)}</dd>
            <dt>Payment terms</dt><dd>{po.payment_terms ?? '—'}</dd>
            <dt>Warranty</dt><dd>{po.warranty ?? '—'}</dd>
            <dt>Value</dt><dd>{formatMoney(po.grand_total, po.currency)}</dd>
            <dt>Ready for dispatch?</dt>
            <dd>{ready ? <span className="badge green">Ready for dispatch</span> : <span className="badge grey">Not yet</span>}</dd>
          </dl>

          <form action={setExpectedDelivery} className="stack" style={{ marginTop: 12 }}>
            <input type="hidden" name="purchase_order_id" value={po.id} />
            <div className="row">
              <div>
                <label htmlFor="expected_delivery_date">Expected delivery *</label>
                <input id="expected_delivery_date" name="expected_delivery_date" type="date"
                  defaultValue={po.expected_delivery_date ?? ''} required />
              </div>
              <div>
                <label htmlFor="payment_terms">Payment terms</label>
                <input id="payment_terms" name="payment_terms" defaultValue={po.payment_terms ?? ''} />
              </div>
              <div>
                <label htmlFor="warranty">Warranty</label>
                <input id="warranty" name="warranty" defaultValue={po.warranty ?? ''} />
              </div>
            </div>
            <button className="btn small" type="submit">Update delivery &amp; terms</button>
          </form>
        </div>

        <div className="card">
          <h3>Purchase approval</h3>
          {approvals.length === 0 ? (
            <p className="muted small">No approval decision yet.</p>
          ) : (
            <ul className="list">
              {approvals.map((a) => (
                <li key={a.id}>
                  <strong>{a.decision}</strong> — step {a.step_no} ·{' '}
                  {a.approver_user_id ? names.get(a.approver_user_id) ?? '—' : '—'} ·{' '}
                  {formatDateTime(a.decided_at ?? a.created_at)}
                  {a.comments ? <div className="hint">{a.comments}</div> : null}
                </li>
              ))}
            </ul>
          )}

          {po.status === 'pending_approval' && canApprove && (
            <form action={decidePurchaseOrder} className="stack" style={{ marginTop: 12 }}>
              <input type="hidden" name="purchase_order_id" value={po.id} />
              <div>
                <label htmlFor="comments">Approval comments</label>
                <textarea id="comments" name="comments" />
              </div>
              <div className="row tight">
                <button className="btn" type="submit" name="decision" value="approved">Approve</button>
                <button className="btn secondary" type="submit" name="decision" value="rejected">Reject</button>
              </div>
            </form>
          )}
          {po.status === 'pending_approval' && !canApprove && (
            <p className="muted small" style={{ marginTop: 12 }}>Waiting for management approval.</p>
          )}
        </div>
      </div>

      <div className="card">
        <h3>Items</h3>
        <table>
          <thead>
            <tr>
              <th className="nowrap">#</th>
              <th>Description</th>
              <th className="nowrap">Qty</th>
              <th className="nowrap">Unit price</th>
              <th className="nowrap">Line total</th>
              <th className="nowrap">Received</th>
              <th className="nowrap">Status</th>
            </tr>
          </thead>
          <tbody>
            {items.map((i) => (
              <tr key={i.id}>
                <td className="nowrap">{i.line_no}</td>
                <td>{i.description}{i.product_name ? <div className="hint">{i.product_name}</div> : null}</td>
                <td className="nowrap">{i.quantity} {i.unit}</td>
                <td className="nowrap">{formatMoney(i.unit_price, po.currency)}</td>
                <td className="nowrap">{formatMoney(i.line_total, po.currency)}</td>
                <td className="nowrap">{i.received_qty}</td>
                <td className="nowrap">{i.status}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <div className="card">
        <h3>Material receipts &amp; PDI</h3>
        {receipts.length === 0 ? (
          <p className="muted small">No receipts yet.</p>
        ) : (
          receipts.map((r) => {
            const pdi = pdis.find((p) => p.material_receipt_id === r.id);
            return (
              <div key={r.id} className="card" style={{ background: '#fafcff' }}>
                <div className="row tight" style={{ justifyContent: 'space-between' }}>
                  <div>
                    <strong>{r.grn_no}</strong> · received {formatDate(r.received_date)} · {r.status} ·
                    inspection {r.inspection_status}
                  </div>
                </div>
                {pdi ? (
                  <p className="muted small" style={{ marginTop: 8 }}>
                    PDI result: <strong>{pdi.result}</strong>
                  </p>
                ) : (
                  <form action={createPdi} className="toolbar" style={{ marginTop: 8 }}>
                    <input type="hidden" name="material_receipt_id" value={r.id} />
                    <input type="hidden" name="purchase_order_id" value={po.id} />
                    <div>
                      <label>Inspection type</label>
                      <select name="inspection_type" defaultValue="pdi">
                        <option value="incoming">Incoming</option>
                        <option value="in_process">In-process</option>
                        <option value="final">Final</option>
                        <option value="pdi">PDI</option>
                        <option value="third_party">Third party</option>
                        <option value="dgqa">DGQA</option>
                        <option value="dgaqa">DGAQA</option>
                      </select>
                    </div>
                    <div>
                      <label>Result</label>
                      <select name="result" defaultValue="pending">
                        <option value="pending">Pending</option>
                        <option value="pass">Pass</option>
                        <option value="fail">Fail</option>
                        <option value="conditional">Conditional</option>
                      </select>
                    </div>
                    <div>
                      <label>Certificate no.</label>
                      <input name="certificate_no" />
                    </div>
                    <button className="btn small" type="submit">Record PDI</button>
                  </form>
                )}
              </div>
            );
          })
        )}

        <form action={recordMaterialReceipt} className="card" style={{ marginTop: 12, background: '#fafcff' }}>
          <input type="hidden" name="purchase_order_id" value={po.id} />
          <h3>Record a material receipt</h3>
          <div className="row">
            <div>
              <label htmlFor="received_date">Received date *</label>
              <input id="received_date" name="received_date" type="date" defaultValue={today} required />
            </div>
            <div>
              <label htmlFor="docket_no">Docket / waybill no.</label>
              <input id="docket_no" name="docket_no" />
            </div>
          </div>
          <div style={{ marginTop: 12 }}>
            <label>Quantities received</label>
            <table>
              <thead>
                <tr>
                  <th className="nowrap">#</th>
                  <th>Description</th>
                  <th className="nowrap">Ordered</th>
                  <th className="nowrap">Received now</th>
                </tr>
              </thead>
              <tbody>
                {items.map((i) => (
                  <tr key={i.id}>
                    <td className="nowrap">{i.line_no}</td>
                    <td>{i.description}</td>
                    <td className="nowrap">{i.quantity}</td>
                    <td><input name={`qty_${i.id}`} type="number" min="0" step="0.001" defaultValue="0" /></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <button className="btn" type="submit" style={{ marginTop: 10 }}>Record receipt</button>
        </form>
      </div>

      <div className="card">
        <h3>Compliance documents</h3>
        {documents.length === 0 ? (
          <p className="muted small">No compliance documents attached.</p>
        ) : (
          <ul className="list">
            {documents.map((d) => (
              <li key={d.id}>
                <strong>{d.doc_type}</strong> — {d.file_name}
                <div className="hint">expires {formatDate(d.expires_on)}</div>
              </li>
            ))}
          </ul>
        )}
        <form action={uploadProcurementDocument} className="toolbar" style={{ marginTop: 12 }}>
          <input type="hidden" name="entity_type" value="purchase_order" />
          <input type="hidden" name="entity_id" value={po.id} />
          <input type="hidden" name="redirect_to" value={`/procurement/orders/${po.id}`} />
          <div>
            <label htmlFor="file">File (max 10 MB)</label>
            <input id="file" name="file" type="file" required />
          </div>
          <div>
            <label htmlFor="doc_type">Document type</label>
            <select id="doc_type" name="doc_type" defaultValue="compliance_certificate">
              <option value="compliance_certificate">Compliance certificate</option>
              <option value="test_certificate">Test certificate</option>
              <option value="iso_certificate">ISO certificate</option>
              <option value="gst_certificate">GST certificate</option>
              <option value="pan">PAN</option>
              <option value="warranty_certificate">Warranty certificate</option>
              <option value="packing_list">Packing list</option>
              <option value="invoice">Invoice</option>
              <option value="other">Other</option>
            </select>
          </div>
          <div>
            <label htmlFor="expires_on">Expires on</label>
            <input id="expires_on" name="expires_on" type="date" />
          </div>
          <button className="btn" type="submit">Upload</button>
        </form>
      </div>
    </>
  );
}
