import Link from 'next/link';
import { DeadlineBadge } from './DeadlineBadge';
import { statusClass, statusLabel } from '@/lib/tenderStatus';
import { formatDate, priorityLabel } from '@/lib/format';
import type { TenderListRow } from '@/lib/data';

/** Simple, readable tender list. One row per tender. */
export function TenderTable({ rows, today }: { rows: TenderListRow[]; today?: Date }) {
  if (rows.length === 0) {
    return <p className="empty">No tenders match these filters.</p>;
  }

  return (
    <div style={{ overflowX: 'auto' }}>
      <table>
        <thead>
          <tr>
            <th className="nowrap">Tender No.</th>
            <th>Title</th>
            <th>Customer</th>
            <th className="nowrap">Status</th>
            <th className="nowrap">Priority</th>
            <th className="nowrap">Closing date</th>
            <th className="nowrap">Deadline</th>
            <th className="nowrap">Assigned</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          {rows.map((t) => (
            <tr key={t.id}>
              <td className="nowrap">
                <Link href={`/tenders/${t.id}`}>{t.tender_no}</Link>
              </td>
              <td>{t.title}</td>
              <td>{t.customer_name}</td>
              <td className="nowrap">
                <span className={statusClass(t.status)}>{statusLabel(t.status)}</span>
              </td>
              <td className="nowrap">{priorityLabel(t.priority)}</td>
              <td className="nowrap">{formatDate(t.bid_due_date)}</td>
              <td className="nowrap">
                <DeadlineBadge dueDate={t.bid_due_date} priority={t.priority} today={today} />
              </td>
              <td className="nowrap">{t.owner_name}</td>
              <td className="nowrap right">
                <Link className="btn small secondary" href={`/tenders/${t.id}/edit`}>
                  Edit
                </Link>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
