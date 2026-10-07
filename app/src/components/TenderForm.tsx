import Link from 'next/link';
import { createTender, updateTender } from '@/app/tenders/actions';
import { TENDER_STATUSES } from '@/lib/tenderStatus';
import type { Customer, Tender, UserDirectoryEntry } from '@/lib/types';

export interface TenderFormProps {
  mode: 'create' | 'edit';
  tender?: Tender;
  customers: Customer[];
  users: UserDirectoryEntry[];
  error?: string;
}

/** Create / edit tender form. Required fields are marked * and enforced server-side. */
export function TenderForm({ mode, tender, customers, users, error }: TenderFormProps) {
  const action = mode === 'create' ? createTender : updateTender;

  return (
    <form action={action} className="stack">
      {error && <div className="alert error">{error}</div>}
      {mode === 'edit' && tender && <input type="hidden" name="id" value={tender.id} />}

      <div className="card">
        <h2>Tender details</h2>
        <div className="row">
          <div>
            <label htmlFor="tender_no">Tender number *</label>
            <input id="tender_no" name="tender_no" defaultValue={tender?.tender_no ?? ''} required />
          </div>
          <div>
            <label htmlFor="customer_id">Customer *</label>
            <select id="customer_id" name="customer_id" defaultValue={tender?.customer_id ?? ''} required>
              <option value="">Select a customer…</option>
              {customers.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name}
                </option>
              ))}
            </select>
          </div>
        </div>

        <div style={{ marginTop: 12 }}>
          <label htmlFor="title">Title *</label>
          <input id="title" name="title" defaultValue={tender?.title ?? ''} required />
        </div>

        <div style={{ marginTop: 12 }}>
          <label htmlFor="description">Description</label>
          <textarea id="description" name="description" defaultValue={tender?.description ?? ''} />
        </div>

        <div className="row" style={{ marginTop: 12 }}>
          <div>
            <label htmlFor="source">Source</label>
            <input id="source" name="source" defaultValue={tender?.source ?? ''} placeholder="e.g. GeM, MoD, direct" />
          </div>
          <div>
            <label htmlFor="category">Category</label>
            <input id="category" name="category" defaultValue={tender?.category ?? ''} />
          </div>
        </div>
      </div>

      <div className="card">
        <h2>Dates, status and priority</h2>
        <div className="row">
          <div>
            <label htmlFor="received_date">Received date *</label>
            <input
              id="received_date"
              name="received_date"
              type="date"
              defaultValue={tender?.received_date ?? ''}
              required
            />
          </div>
          <div>
            <label htmlFor="bid_due_date">Closing date</label>
            <input
              id="bid_due_date"
              name="bid_due_date"
              type="date"
              defaultValue={tender?.bid_due_date ?? ''}
            />
            <div className="hint">Used for the green / yellow / red deadline indicator.</div>
          </div>
          <div>
            <label htmlFor="priority">Priority</label>
            <select id="priority" name="priority" defaultValue={tender?.priority ?? 'medium'}>
              <option value="low">Low</option>
              <option value="medium">Medium</option>
              <option value="high">High</option>
              <option value="critical">Critical</option>
            </select>
          </div>
        </div>

        <div className="row" style={{ marginTop: 12 }}>
          <div>
            <label htmlFor="status">Status</label>
            <select id="status" name="status" defaultValue={tender?.status ?? 'new'}>
              {TENDER_STATUSES.map((s) => (
                <option key={s.code} value={s.code}>
                  {s.label}
                </option>
              ))}
            </select>
          </div>
          <div>
            <label htmlFor="owner_user_id">Assigned employee</label>
            <select id="owner_user_id" name="owner_user_id" defaultValue={tender?.owner_user_id ?? ''}>
              <option value="">Unassigned</option>
              {users.map((u) => (
                <option key={u.id} value={u.id}>
                  {u.full_name}
                  {u.designation ? ` — ${u.designation}` : ''}
                </option>
              ))}
            </select>
          </div>
        </div>
      </div>

      <div className="card">
        <h2>Commercials and notes</h2>
        <div className="row">
          <div>
            <label htmlFor="emd_amount">EMD amount</label>
            <input
              id="emd_amount"
              name="emd_amount"
              type="number"
              min="0"
              step="0.01"
              defaultValue={tender?.emd_amount ?? ''}
            />
          </div>
          <div>
            <label htmlFor="currency">Currency</label>
            <input id="currency" name="currency" defaultValue={tender?.currency ?? 'INR'} />
          </div>
        </div>
        <div style={{ marginTop: 12 }}>
          <label htmlFor="notes">Notes</label>
          <textarea id="notes" name="notes" defaultValue={tender?.notes ?? ''} />
        </div>
      </div>

      <div className="row tight">
        <button className="btn" type="submit">
          {mode === 'create' ? 'Create tender' : 'Save changes'}
        </button>
        <Link className="btn secondary" href={mode === 'edit' && tender ? `/tenders/${tender.id}` : '/tenders'}>
          Cancel
        </Link>
      </div>
    </form>
  );
}
