import Link from 'next/link';
import {
  addMaterialRequirementItem,
  createOemRfqs,
  createPurchaseRequest,
} from '../../actions';
import {
  getMaterialRequirement,
  getMaterialRequirementItems,
  getOemRfqsForRequirement,
  getPurchaseRequestsForRequirement,
  listOems,
  listProducts,
} from '@/lib/data';
import { labelFor, MATERIAL_REQUIREMENT_STATUSES, RFQ_STATUSES } from '@/lib/procurement';
import { formatDate } from '@/lib/format';

export const dynamic = 'force-dynamic';

export default async function MaterialRequirementPage({
  params,
  searchParams,
}: {
  params: { id: string };
  searchParams: { error?: string };
}) {
  const requirement = await getMaterialRequirement(params.id);
  if (!requirement) {
    return (
      <>
        <h1>Material requirement not found</h1>
        <Link href="/procurement">← Back to procurement</Link>
      </>
    );
  }

  const [items, requests, rfqs, oems, products] = await Promise.all([
    getMaterialRequirementItems(params.id),
    getPurchaseRequestsForRequirement(params.id),
    getOemRfqsForRequirement(params.id),
    listOems(),
    listProducts(),
  ]);

  const oemNames = new Map(oems.map((o) => [o.id, o.name]));

  return (
    <>
      {searchParams.error && <div className="alert error">{searchParams.error}</div>}

      <div className="section-head">
        <div>
          <h1>{requirement.requirement_no}</h1>
          <p className="subtitle">
            <span className="chip">{labelFor(MATERIAL_REQUIREMENT_STATUSES, requirement.status)}</span>{' '}
            · required by {formatDate(requirement.required_by_date)} · priority {requirement.priority}
          </p>
        </div>
        <Link className="btn secondary" href="/procurement">← Procurement</Link>
      </div>

      <div className="card">
        <h3>Requirement lines</h3>
        {items.length === 0 ? (
          <p className="muted small">No lines yet.</p>
        ) : (
          <table>
            <thead>
              <tr>
                <th className="nowrap">#</th>
                <th>Description</th>
                <th className="nowrap">Qty</th>
                <th className="nowrap">Unit</th>
                <th className="nowrap">Required by</th>
                <th className="nowrap">Status</th>
              </tr>
            </thead>
            <tbody>
              {items.map((i) => (
                <tr key={i.id}>
                  <td className="nowrap">{i.line_no}</td>
                  <td>{i.description}</td>
                  <td className="nowrap">{i.quantity}</td>
                  <td className="nowrap">{i.unit}</td>
                  <td className="nowrap">{formatDate(i.required_by)}</td>
                  <td className="nowrap">{i.status}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}

        <form action={addMaterialRequirementItem} className="stack" style={{ marginTop: 14 }}>
          <input type="hidden" name="requirement_id" value={requirement.id} />
          <div className="row">
            <div style={{ flex: '1 1 320px' }}>
              <label htmlFor="description">Description *</label>
              <input id="description" name="description" required />
            </div>
            <div>
              <label htmlFor="product_id">Product (optional)</label>
              <select id="product_id" name="product_id" defaultValue="">
                <option value="">—</option>
                {products.map((p) => (
                  <option key={p.id} value={p.id}>{p.code} — {p.name}</option>
                ))}
              </select>
            </div>
            <div>
              <label htmlFor="quantity">Quantity *</label>
              <input id="quantity" name="quantity" type="number" min="0.001" step="0.001" required />
            </div>
            <div>
              <label htmlFor="unit">Unit</label>
              <input id="unit" name="unit" defaultValue="NO" />
            </div>
            <div>
              <label htmlFor="required_by">Required by</label>
              <input id="required_by" name="required_by" type="date" />
            </div>
          </div>
          <button className="btn small" type="submit">Add line</button>
        </form>
      </div>

      <div className="grid2">
        <div className="card">
          <h3>Purchase request</h3>
          {requests.length === 0 ? (
            <p className="muted small">No purchase request yet.</p>
          ) : (
            <ul className="list">
              {requests.map((r) => (
                <li key={r.id}>
                  <strong>{r.request_no}</strong>
                  <div className="hint">needed by {formatDate(r.needed_by)} · {r.status}</div>
                </li>
              ))}
            </ul>
          )}
          <form action={createPurchaseRequest} style={{ marginTop: 12 }}>
            <input type="hidden" name="requirement_id" value={requirement.id} />
            <button className="btn small" type="submit">Create purchase request</button>
          </form>
        </div>

        <div className="card">
          <h3>OEM RFQs</h3>
          {rfqs.length === 0 ? (
            <p className="muted small">No RFQs sent yet.</p>
          ) : (
            <ul className="list">
              {rfqs.map((r) => (
                <li key={r.id}>
                  <Link href={`/procurement/rfqs/${r.id}`}>
                    {r.rfq_no} — {oemNames.get(r.oem_id) ?? 'OEM'}
                  </Link>
                  <div className="hint">{labelFor(RFQ_STATUSES, r.status)} · due {formatDate(r.due_date)}</div>
                </li>
              ))}
            </ul>
          )}

          <form action={createOemRfqs} className="stack" style={{ marginTop: 12 }}>
            <input type="hidden" name="requirement_id" value={requirement.id} />
            <div>
              <label>Send RFQ to OEMs</label>
              {oems.length === 0 ? (
                <p className="muted small">No OEMs on file.</p>
              ) : (
                <div className="stack" style={{ gap: 4 }}>
                  {oems.map((o) => (
                    <label key={o.id} className="checkbox">
                      <input type="checkbox" name="oem_ids" value={o.id} /> {o.name}
                    </label>
                  ))}
                </div>
              )}
            </div>
            <div>
              <label htmlFor="due_date">Quote due date</label>
              <input id="due_date" name="due_date" type="date" />
            </div>
            <button className="btn small" type="submit">Send RFQs</button>
          </form>
        </div>
      </div>
    </>
  );
}
