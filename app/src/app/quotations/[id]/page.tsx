import Link from 'next/link';
import {
  addFollowUpTask,
  addQuotationItem,
  createRevision,
  decideQuotation,
  removeQuotationItem,
  setQuotationStatus,
  submitForApproval,
} from '../actions';
import {
  getCurrentContext,
  getQuotation,
  getQuotationActivity,
  getQuotationApprovals,
  getQuotationItems,
  getQuotationRevisions,
  getQuotationTasks,
  getRequirements,
  getUserDirectory,
  listOems,
  listProducts,
} from '@/lib/data';
import {
  COMPLIANCE_VALUES,
  QUOTATION_STATUSES,
  complianceClass,
  complianceLabel,
  complianceRollup,
  isFrozen,
  marginPercent,
  quotationStatusClass,
  quotationStatusLabel,
} from '@/lib/quotation';
import { formatDate, formatDateTime, formatMoney } from '@/lib/format';

export const dynamic = 'force-dynamic';

export default async function QuotationDetailPage({
  params,
  searchParams,
}: {
  params: { id: string };
  searchParams: { error?: string };
}) {
  const id = params.id;
  const quotation = await getQuotation(id);
  if (!quotation) {
    return (
      <>
        <h1>Quotation not found</h1>
        <Link href="/quotations">← Back to quotations</Link>
      </>
    );
  }

  const [items, approvals, revisions, tasks, activity, users, oems, products, me] = await Promise.all([
    getQuotationItems(id),
    getQuotationApprovals(id),
    getQuotationRevisions(quotation.quotation_no),
    getQuotationTasks(id),
    getQuotationActivity(id),
    getUserDirectory(),
    listOems(),
    listProducts(),
    getCurrentContext(),
  ]);

  const requirements = quotation.tender_id ? await getRequirements(quotation.tender_id) : [];
  const names = new Map(users.map((u) => [u.id, u.full_name]));
  const frozen = isFrozen(quotation.status);
  const canApprove = !!me && (me.roles.includes('admin') || me.roles.includes('management'));
  const marginPct = marginPercent(quotation.subtotal, quotation.total_margin);

  return (
    <>
      {searchParams.error && <div className="alert error">{searchParams.error}</div>}

      <div className="section-head">
        <div>
          <h1>
            {quotation.quotation_no} <span className="chip">v{quotation.version}</span>
          </h1>
          <p className="subtitle">
            <span className={quotationStatusClass(quotation.status)}>{quotationStatusLabel(quotation.status)}</span>{' '}
            · {quotation.customer_name}
            {quotation.tender_no ? (
              <>
                {' '}
                · tender {quotation.tender_no}
              </>
            ) : null}
          </p>
        </div>
        <div className="row tight">
          <a className="btn secondary" href={`/quotations/${quotation.id}/pdf`}>
            Download PDF
          </a>
          {!frozen && (
            <Link className="btn secondary" href={`/quotations/${quotation.id}/edit`}>
              Edit header
            </Link>
          )}
          <form action={createRevision}>
            <input type="hidden" name="quotation_id" value={quotation.id} />
            <button className="btn" type="submit">
              Create revision
            </button>
          </form>
        </div>
      </div>

      {frozen && (
        <div className="alert info">
          This quotation is <strong>{quotationStatusLabel(quotation.status)}</strong> and is frozen. It
          cannot be edited — use <strong>Create revision</strong> to make changes.
        </div>
      )}

      <div className="grid3">
        <div className="card">
          <h3>Commercials</h3>
          <dl className="kv">
            <dt>Net (ex-tax)</dt>
            <dd>{formatMoney(quotation.subtotal, quotation.currency)}</dd>
            <dt>GST</dt>
            <dd>{formatMoney(quotation.tax_total, quotation.currency)}</dd>
            <dt><strong>Grand total</strong></dt>
            <dd><strong>{formatMoney(quotation.grand_total, quotation.currency)}</strong></dd>
          </dl>
        </div>
        <div className="card">
          <h3>Cost &amp; margin</h3>
          <dl className="kv">
            <dt>Purchase cost</dt>
            <dd>{formatMoney(quotation.total_purchase_cost, quotation.currency)}</dd>
            <dt>Logistics</dt>
            <dd>{formatMoney(quotation.total_logistics_cost, quotation.currency)}</dd>
            <dt>Other cost</dt>
            <dd>{formatMoney(quotation.total_other_cost, quotation.currency)}</dd>
            <dt><strong>Margin</strong></dt>
            <dd>
              <strong>{formatMoney(quotation.total_margin, quotation.currency)}</strong>
              {marginPct !== null ? ` (${marginPct}%)` : ''}
            </dd>
          </dl>
        </div>
        <div className="card">
          <h3>Terms</h3>
          <dl className="kv">
            <dt>Payment</dt>
            <dd>{quotation.payment_terms ?? '—'}</dd>
            <dt>Delivery</dt>
            <dd>{quotation.delivery_terms ?? '—'}</dd>
            <dt>Warranty</dt>
            <dd>{quotation.warranty ?? '—'}</dd>
            <dt>Valid until</dt>
            <dd>{formatDate(quotation.validity_date)}</dd>
            <dt>Technical</dt>
            <dd>
              <span className={complianceClass(complianceRollup(items))}>
                {complianceLabel(complianceRollup(items))}
              </span>
            </dd>
          </dl>
        </div>
      </div>

      {/* Line items */}
      <div className="card">
        <div className="section-head">
          <h3>Products</h3>
        </div>
        {items.length === 0 ? (
          <p className="muted small">No products yet. Add the first line below.</p>
        ) : (
          <div style={{ overflowX: 'auto' }}>
            <table>
              <thead>
                <tr>
                  <th className="nowrap">#</th>
                  <th>Description</th>
                  <th className="nowrap">Qty</th>
                  <th className="nowrap">Purchase</th>
                  <th className="nowrap">Logistics</th>
                  <th className="nowrap">Other</th>
                  <th className="nowrap">Cost</th>
                  <th className="nowrap">Selling</th>
                  <th className="nowrap">Disc %</th>
                  <th className="nowrap">GST %</th>
                  <th className="nowrap">Line total</th>
                  <th className="nowrap">Margin</th>
                  <th className="nowrap">Margin %</th>
                  <th className="nowrap">Compliance</th>
                  {!frozen && <th></th>}
                </tr>
              </thead>
              <tbody>
                {items.map((it) => (
                  <tr key={it.id}>
                    <td className="nowrap">{it.line_no}</td>
                    <td>
                      {it.description}
                      {it.source_oem_id ? (
                        <div className="hint">OEM: {oems.find((o) => o.id === it.source_oem_id)?.name ?? '—'}</div>
                      ) : null}
                    </td>
                    <td className="nowrap">{it.quantity} {it.unit}</td>
                    <td className="nowrap">{formatMoney(it.purchase_unit_cost, quotation.currency)}</td>
                    <td className="nowrap">{formatMoney(it.logistics_unit_cost, quotation.currency)}</td>
                    <td className="nowrap">{formatMoney(it.other_unit_cost, quotation.currency)}</td>
                    <td className="nowrap">{formatMoney(it.line_cost, quotation.currency)}</td>
                    <td className="nowrap">{formatMoney(it.unit_price, quotation.currency)}</td>
                    <td className="nowrap">{it.discount_pct}</td>
                    <td className="nowrap">{it.tax_pct}</td>
                    <td className="nowrap">{formatMoney(it.line_total, quotation.currency)}</td>
                    <td className="nowrap">{formatMoney(it.line_margin, quotation.currency)}</td>
                    <td className="nowrap">{it.line_margin_pct ?? '—'}</td>
                    <td className="nowrap">
                      <span className={complianceClass(it.technical_compliance)}>
                        {complianceLabel(it.technical_compliance)}
                      </span>
                    </td>
                    {!frozen && (
                      <td className="nowrap right">
                        <form action={removeQuotationItem}>
                          <input type="hidden" name="quotation_id" value={quotation.id} />
                          <input type="hidden" name="item_id" value={it.id} />
                          <button className="btn small ghost" type="submit">
                            Remove
                          </button>
                        </form>
                      </td>
                    )}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        {!frozen && (
          <form action={addQuotationItem} className="stack" style={{ marginTop: 16 }}>
            <input type="hidden" name="quotation_id" value={quotation.id} />
            <h3>Add a product</h3>
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
                    <option key={p.id} value={p.id}>
                      {p.code} — {p.name}
                    </option>
                  ))}
                </select>
              </div>
              <div>
                <label htmlFor="source_oem_id">OEM (optional)</label>
                <select id="source_oem_id" name="source_oem_id" defaultValue="">
                  <option value="">—</option>
                  {oems.map((o) => (
                    <option key={o.id} value={o.id}>
                      {o.name}
                    </option>
                  ))}
                </select>
              </div>
              {requirements.length > 0 && (
                <div>
                  <label htmlFor="tender_requirement_id">Tender requirement (optional)</label>
                  <select id="tender_requirement_id" name="tender_requirement_id" defaultValue="">
                    <option value="">—</option>
                    {requirements.map((r) => (
                      <option key={r.id} value={r.id}>
                        {r.line_no}. {r.description}
                      </option>
                    ))}
                  </select>
                </div>
              )}
            </div>

            <div className="row">
              <div>
                <label htmlFor="quantity">Quantity *</label>
                <input id="quantity" name="quantity" type="number" min="0.001" step="0.001" required />
              </div>
              <div>
                <label htmlFor="unit">Unit</label>
                <input id="unit" name="unit" defaultValue="NO" />
              </div>
              <div>
                <label htmlFor="purchase_unit_cost">Purchase cost / unit *</label>
                <input id="purchase_unit_cost" name="purchase_unit_cost" type="number" min="0" step="0.01" defaultValue="0" required />
              </div>
              <div>
                <label htmlFor="logistics_unit_cost">Logistics / unit</label>
                <input id="logistics_unit_cost" name="logistics_unit_cost" type="number" min="0" step="0.01" defaultValue="0" />
              </div>
              <div>
                <label htmlFor="other_unit_cost">Other cost / unit</label>
                <input id="other_unit_cost" name="other_unit_cost" type="number" min="0" step="0.01" defaultValue="0" />
              </div>
              <div>
                <label htmlFor="unit_price">Selling price / unit *</label>
                <input id="unit_price" name="unit_price" type="number" min="0" step="0.01" required />
              </div>
              <div>
                <label htmlFor="discount_pct">Discount %</label>
                <input id="discount_pct" name="discount_pct" type="number" min="0" max="100" step="0.01" defaultValue="0" />
              </div>
              <div>
                <label htmlFor="tax_pct">GST %</label>
                <input id="tax_pct" name="tax_pct" type="number" min="0" max="100" step="0.01" defaultValue="18" />
              </div>
              <div>
                <label htmlFor="technical_compliance">Technical compliance</label>
                <select id="technical_compliance" name="technical_compliance" defaultValue="pending">
                  {COMPLIANCE_VALUES.map((c) => (
                    <option key={c.code} value={c.code}>
                      {c.label}
                    </option>
                  ))}
                </select>
              </div>
            </div>
            <button className="btn" type="submit">
              Add product line
            </button>
          </form>
        )}
      </div>

      <div className="grid2">
        {/* Approval workflow */}
        <div className="card">
          <h3>Approval workflow</h3>
          {approvals.length === 0 ? (
            <p className="muted small">No approval decisions yet.</p>
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

          {quotation.status === 'draft' && (
            <form action={submitForApproval} style={{ marginTop: 12 }}>
              <input type="hidden" name="id" value={quotation.id} />
              <button className="btn" type="submit">
                Submit for approval
              </button>
            </form>
          )}

          {quotation.status === 'pending_approval' && canApprove && (
            <form action={decideQuotation} className="stack" style={{ marginTop: 12 }}>
              <input type="hidden" name="id" value={quotation.id} />
              <div>
                <label htmlFor="comments">Approval comments</label>
                <textarea id="comments" name="comments" />
              </div>
              <div className="row tight">
                <button className="btn" type="submit" name="decision" value="approved">
                  Approve
                </button>
                <button className="btn secondary" type="submit" name="decision" value="rejected">
                  Reject
                </button>
              </div>
            </form>
          )}

          {quotation.status === 'pending_approval' && !canApprove && (
            <p className="muted small" style={{ marginTop: 12 }}>
              Waiting for management approval.
            </p>
          )}

          <form action={setQuotationStatus} className="toolbar" style={{ marginTop: 14 }}>
            <input type="hidden" name="id" value={quotation.id} />
            <div>
              <label htmlFor="status">Set status</label>
              <select id="status" name="status" defaultValue={quotation.status}>
                {QUOTATION_STATUSES.map((s) => (
                  <option key={s.code} value={s.code}>
                    {s.label}
                  </option>
                ))}
              </select>
            </div>
            <button className="btn secondary" type="submit">
              Update
            </button>
          </form>
        </div>

        {/* Follow-up */}
        <div className="card">
          <h3>Follow-up tasks</h3>
          <form action={addFollowUpTask} className="stack" style={{ marginBottom: 12 }}>
            <input type="hidden" name="quotation_id" value={quotation.id} />
            <div>
              <label htmlFor="title">Add a follow-up</label>
              <input id="title" name="title" placeholder="e.g. Call customer about quotation" required />
            </div>
            <div className="row">
              <div>
                <label>Assign to</label>
                <select name="assigned_to" defaultValue="">
                  <option value="">Unassigned</option>
                  {users.map((u) => (
                    <option key={u.id} value={u.id}>
                      {u.full_name}
                    </option>
                  ))}
                </select>
              </div>
              <div>
                <label>Due date</label>
                <input name="due_date" type="date" />
              </div>
            </div>
            <button className="btn small" type="submit">
              Add follow-up
            </button>
          </form>

          {tasks.length === 0 ? (
            <p className="muted small">No follow-up tasks yet.</p>
          ) : (
            <ul className="list">
              {tasks.map((t) => (
                <li key={t.id}>
                  <strong>{t.title}</strong>
                  <div className="hint">
                    {t.status} · {t.assigned_to ? names.get(t.assigned_to) ?? '—' : 'Unassigned'} ·{' '}
                    {t.due_date ? `due ${formatDate(t.due_date)}` : 'no due date'}
                  </div>
                </li>
              ))}
            </ul>
          )}
        </div>
      </div>

      {/* Revision history */}
      <div className="card">
        <h3>Revision history</h3>
        <table>
          <thead>
            <tr>
              <th className="nowrap">Version</th>
              <th className="nowrap">Status</th>
              <th className="nowrap">Grand total</th>
              <th className="nowrap">Created</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {revisions.map((r) => (
              <tr key={r.id}>
                <td className="nowrap">
                  v{r.version} {r.id === quotation.id ? <span className="chip">current</span> : null}
                </td>
                <td className="nowrap">
                  <span className={quotationStatusClass(r.status)}>{quotationStatusLabel(r.status)}</span>
                </td>
                <td className="nowrap">{formatMoney(r.grand_total, r.currency)}</td>
                <td className="nowrap">{formatDateTime(r.created_at)}</td>
                <td className="nowrap right">
                  {r.id !== quotation.id && (
                    <Link className="btn small secondary" href={`/quotations/${r.id}`}>
                      Open
                    </Link>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {/* Activity */}
      <div className="card">
        <h3>Activity history</h3>
        {activity.length === 0 ? (
          <p className="muted small">No recorded activity yet.</p>
        ) : (
          <ul className="list">
            {activity.map((a) => (
              <li key={a.id}>
                <strong>{a.action}</strong> — {a.actor_user_id ? names.get(a.actor_user_id) ?? 'Unknown' : 'System'} ·{' '}
                {formatDateTime(a.created_at)}
              </li>
            ))}
          </ul>
        )}
      </div>
    </>
  );
}
