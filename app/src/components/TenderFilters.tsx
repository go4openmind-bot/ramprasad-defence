import Link from 'next/link';
import { TENDER_STATUSES } from '@/lib/tenderStatus';
import type { UserDirectoryEntry } from '@/lib/types';

export interface FilterValues {
  q?: string;
  status?: string;
  priority?: string;
  owner?: string;
  deadline?: string;
}

/**
 * Search + filters as a plain GET form, so it works with no JavaScript and is
 * easy for non-technical staff. Submitting reloads the list with the filters.
 */
export function TenderFilters({ values, users }: { values: FilterValues; users: UserDirectoryEntry[] }) {
  return (
    <form className="toolbar" method="get" action="/tenders">
      <div style={{ flex: '1 1 260px' }}>
        <label htmlFor="q">Search</label>
        <input id="q" name="q" defaultValue={values.q ?? ''} placeholder="Tender number or title" />
      </div>

      <div>
        <label htmlFor="status">Status</label>
        <select id="status" name="status" defaultValue={values.status ?? ''}>
          <option value="">All statuses</option>
          {TENDER_STATUSES.map((s) => (
            <option key={s.code} value={s.code}>
              {s.label}
            </option>
          ))}
        </select>
      </div>

      <div>
        <label htmlFor="priority">Priority</label>
        <select id="priority" name="priority" defaultValue={values.priority ?? ''}>
          <option value="">All priorities</option>
          <option value="low">Low</option>
          <option value="medium">Medium</option>
          <option value="high">High</option>
          <option value="critical">Critical</option>
        </select>
      </div>

      <div>
        <label htmlFor="owner">Assigned to</label>
        <select id="owner" name="owner" defaultValue={values.owner ?? ''}>
          <option value="">Anyone</option>
          {users.map((u) => (
            <option key={u.id} value={u.id}>
              {u.full_name}
            </option>
          ))}
        </select>
      </div>

      <div>
        <label htmlFor="deadline">Deadline</label>
        <select id="deadline" name="deadline" defaultValue={values.deadline ?? ''}>
          <option value="">Any</option>
          <option value="red">Red — overdue / high risk</option>
          <option value="yellow">Yellow — approaching</option>
          <option value="green">Green — normal</option>
        </select>
      </div>

      <button className="btn" type="submit">
        Apply
      </button>
      <Link className="btn secondary" href="/tenders">
        Reset
      </Link>
    </form>
  );
}
