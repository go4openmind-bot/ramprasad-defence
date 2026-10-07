import Link from 'next/link';
import { DeadlineBadge } from '@/components/DeadlineBadge';
import { StatusPipeline } from '@/components/StatusPipeline';
import { statusClass, statusLabel, TENDER_STATUSES } from '@/lib/tenderStatus';
import { formatDate, formatDateTime, formatMoney, priorityLabel } from '@/lib/format';
import {
  getActivity,
  getDocuments,
  getDocumentUrl,
  getNotes,
  getRequirements,
  getTasks,
  getTender,
  getUserDirectory,
} from '@/lib/data';
import {
  addNote,
  addRequirement,
  addTask,
  assignTender,
  completeTask,
  setTenderStatus,
  uploadDocument,
} from '../actions';

export const dynamic = 'force-dynamic';

export default async function TenderDetailPage({
  params,
  searchParams,
}: {
  params: { id: string };
  searchParams: { error?: string };
}) {
  const id = params.id;
  const tender = await getTender(id);

  if (!tender) {
    return (
      <>
        <h1>Tender not found</h1>
        <p className="subtitle">It may have been deleted, or you may not have access to it.</p>
        <Link href="/tenders">← Back to tenders</Link>
      </>
    );
  }

  const [requirements, notes, tasks, documents, activity, users] = await Promise.all([
    getRequirements(id),
    getNotes(id),
    getTasks(id),
    getDocuments(id),
    getActivity(id),
    getUserDirectory(),
  ]);

  const docs = await Promise.all(
    documents.map(async (d) => ({ ...d, url: await getDocumentUrl(d.storage_path) })),
  );
  const names = new Map(users.map((u) => [u.id, u.full_name]));
  const ownerName = tender.owner_user_id ? names.get(tender.owner_user_id) ?? '—' : 'Unassigned';

  return (
    <>
      {searchParams.error && <div className="alert error">{searchParams.error}</div>}

      <div className="section-head">
        <div>
          <h1>
            {tender.tender_no} — {tender.title}
          </h1>
          <p className="subtitle">
            <span className={statusClass(tender.status)}>{statusLabel(tender.status)}</span>{' '}
            <DeadlineBadge dueDate={tender.bid_due_date} priority={tender.priority} /> Priority:{' '}
            {priorityLabel(tender.priority)}
          </p>
        </div>
        <div className="row tight">
          <Link className="btn secondary" href="/tenders">
            ← All tenders
          </Link>
          <Link
            className="btn secondary"
            href={`/quotations/new?tender_id=${tender.id}&customer_id=${tender.customer_id}`}
          >
            Create quotation
          </Link>
          <Link className="btn" href={`/tenders/${tender.id}/edit`}>
            Edit
          </Link>
        </div>
      </div>

      <div className="card">
        <h3>Status pipeline</h3>
        <StatusPipeline current={tender.status} />
        <div className="toolbar" style={{ marginTop: 14 }}>
          <form action={setTenderStatus} className="toolbar">
            <input type="hidden" name="id" value={tender.id} />
            <div>
              <label htmlFor="status">Move to status</label>
              <select id="status" name="status" defaultValue={tender.status}>
                {TENDER_STATUSES.map((s) => (
                  <option key={s.code} value={s.code}>
                    {s.label}
                  </option>
                ))}
              </select>
            </div>
            <button className="btn" type="submit">
              Update status
            </button>
          </form>

          <form action={assignTender} className="toolbar">
            <input type="hidden" name="id" value={tender.id} />
            <div>
              <label htmlFor="owner_user_id">Assign to employee</label>
              <select id="owner_user_id" name="owner_user_id" defaultValue={tender.owner_user_id ?? ''}>
                <option value="">Unassigned</option>
                {users.map((u) => (
                  <option key={u.id} value={u.id}>
                    {u.full_name}
                    {u.designation ? ` — ${u.designation}` : ''}
                  </option>
                ))}
              </select>
            </div>
            <button className="btn" type="submit">
              Assign
            </button>
          </form>
        </div>
      </div>

      <div className="grid2">
        <div className="card">
          <h3>Key details</h3>
          <dl className="kv">
            <dt>Customer</dt>
            <dd>{tender.customer_name}</dd>
            <dt>Received date</dt>
            <dd>{formatDate(tender.received_date)}</dd>
            <dt>Closing date</dt>
            <dd>{formatDate(tender.bid_due_date)}</dd>
            <dt>EMD amount</dt>
            <dd>{formatMoney(tender.emd_amount, tender.currency)}</dd>
            <dt>Source</dt>
            <dd>{tender.source ?? '—'}</dd>
            <dt>Category</dt>
            <dd>{tender.category ?? '—'}</dd>
            <dt>Assigned to</dt>
            <dd>{ownerName}</dd>
            <dt>Last updated</dt>
            <dd>{formatDateTime(tender.updated_at)}</dd>
          </dl>
          {tender.description && (
            <>
              <h3 style={{ marginTop: 16 }}>Description</h3>
              <p className="small">{tender.description}</p>
            </>
          )}
          {tender.notes && (
            <>
              <h3 style={{ marginTop: 16 }}>Summary notes</h3>
              <p className="small">{tender.notes}</p>
            </>
          )}
        </div>

        {/* Requirements */}
        <div className="card">
          <h3>Requirement section</h3>
          {requirements.length === 0 ? (
            <p className="muted small">No requirement lines yet.</p>
          ) : (
            <table>
              <thead>
                <tr>
                  <th className="nowrap">#</th>
                  <th>Description</th>
                  <th className="nowrap">Qty</th>
                  <th className="nowrap">Unit</th>
                </tr>
              </thead>
              <tbody>
                {requirements.map((r) => (
                  <tr key={r.id}>
                    <td className="nowrap">{r.line_no}</td>
                    <td>
                      {r.description}
                      {r.specification ? <div className="hint">{r.specification}</div> : null}
                    </td>
                    <td className="nowrap">{r.quantity}</td>
                    <td className="nowrap">{r.unit}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}

          <form action={addRequirement} className="stack" style={{ marginTop: 14 }}>
            <input type="hidden" name="tender_id" value={tender.id} />
            <div>
              <label>Add requirement</label>
              <input name="description" placeholder="Requirement description" required />
            </div>
            <div className="row">
              <div>
                <label>Specification</label>
                <input name="specification" placeholder="Technical specification" />
              </div>
              <div>
                <label>Quantity</label>
                <input name="quantity" type="number" min="0.001" step="0.001" required />
              </div>
              <div>
                <label>Unit</label>
                <input name="unit" defaultValue="NO" />
              </div>
            </div>
            <button className="btn small" type="submit">
              Add requirement
            </button>
          </form>
        </div>
      </div>

      <div className="grid2">
        {/* Notes */}
        <div className="card">
          <h3>Notes</h3>
          <form action={addNote} style={{ marginBottom: 12 }}>
            <input type="hidden" name="tender_id" value={tender.id} />
            <label htmlFor="note">Add a note</label>
            <textarea id="note" name="note" placeholder="Write a note…" required />
            <button className="btn small" type="submit" style={{ marginTop: 8 }}>
              Add note
            </button>
          </form>
          {notes.length === 0 ? (
            <p className="muted small">No notes yet.</p>
          ) : (
            <ul className="list">
              {notes.map((n) => (
                <li key={n.id}>
                  <div>{n.note}</div>
                  <div className="hint">
                    {n.created_by ? names.get(n.created_by) ?? 'Unknown' : 'System'} ·{' '}
                    {formatDateTime(n.created_at)}
                  </div>
                </li>
              ))}
            </ul>
          )}
        </div>

        {/* Tasks */}
        <div className="card">
          <h3>Tasks</h3>
          <form action={addTask} className="stack" style={{ marginBottom: 12 }}>
            <input type="hidden" name="tender_id" value={tender.id} />
            <div>
              <label htmlFor="title">Add a task</label>
              <input id="title" name="title" placeholder="What needs to be done?" required />
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
              <div>
                <label>Priority</label>
                <select name="priority" defaultValue="medium">
                  <option value="low">Low</option>
                  <option value="medium">Medium</option>
                  <option value="high">High</option>
                  <option value="critical">Critical</option>
                </select>
              </div>
            </div>
            <button className="btn small" type="submit">
              Add task
            </button>
          </form>

          {tasks.length === 0 ? (
            <p className="muted small">No tasks yet.</p>
          ) : (
            <ul className="list">
              {tasks.map((t) => (
                <li key={t.id}>
                  <div className="row tight" style={{ justifyContent: 'space-between' }}>
                    <div>
                      <strong>{t.title}</strong>
                      <div className="hint">
                        {t.status === 'done' ? 'Done' : priorityLabel(t.priority)} ·{' '}
                        {t.assigned_to ? names.get(t.assigned_to) ?? '—' : 'Unassigned'} ·{' '}
                        {t.due_date ? `due ${formatDate(t.due_date)}` : 'no due date'}
                      </div>
                    </div>
                    {t.status !== 'done' && (
                      <form action={completeTask}>
                        <input type="hidden" name="id" value={t.id} />
                        <input type="hidden" name="tender_id" value={tender.id} />
                        <button className="btn small secondary" type="submit">
                          Mark done
                        </button>
                      </form>
                    )}
                  </div>
                </li>
              ))}
            </ul>
          )}
        </div>
      </div>

      {/* Documents */}
      <div className="card">
        <h3>Approved tender documents</h3>
        {docs.length === 0 ? (
          <p className="muted small">No documents uploaded yet.</p>
        ) : (
          <table>
            <thead>
              <tr>
                <th>File</th>
                <th className="nowrap">Type</th>
                <th className="nowrap">Classification</th>
                <th className="nowrap">Uploaded</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              {docs.map((d) => (
                <tr key={d.id}>
                  <td>{d.file_name}</td>
                  <td className="nowrap">{d.doc_type}</td>
                  <td className="nowrap">
                    <span className="chip">{d.classification}</span>
                  </td>
                  <td className="nowrap">{formatDateTime(d.created_at)}</td>
                  <td className="nowrap right">
                    {d.url ? (
                      <a className="btn small secondary" href={d.url} target="_blank" rel="noreferrer">
                        Download
                      </a>
                    ) : (
                      <span className="hint">unavailable</span>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}

        <form action={uploadDocument} className="card" style={{ marginTop: 14, background: '#fafcff' }}>
          <input type="hidden" name="tender_id" value={tender.id} />
          <div className="row">
            <div>
              <label htmlFor="file">Upload document (max 10 MB)</label>
              <input id="file" name="file" type="file" required />
            </div>
            <div>
              <label htmlFor="doc_type">Document type</label>
              <select id="doc_type" name="doc_type" defaultValue="tender_document">
                <option value="tender_document">Tender document</option>
                <option value="corrigendum">Corrigendum</option>
                <option value="technical_spec">Technical specification</option>
                <option value="drawing">Drawing</option>
                <option value="emd_proof">EMD proof</option>
                <option value="other">Other</option>
              </select>
            </div>
            <div>
              <label htmlFor="classification">Classification</label>
              <select id="classification" name="classification" defaultValue="internal">
                <option value="unclassified">Unclassified</option>
                <option value="internal">Internal</option>
                <option value="confidential">Confidential</option>
                <option value="controlled">Controlled</option>
                <option value="itar_ear">ITAR / EAR</option>
              </select>
            </div>
          </div>
          <button className="btn" type="submit" style={{ marginTop: 10 }}>
            Upload document
          </button>
        </form>
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
