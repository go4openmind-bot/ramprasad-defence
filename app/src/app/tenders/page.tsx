import Link from 'next/link';
import { TenderFilters } from '@/components/TenderFilters';
import { TenderTable } from '@/components/TenderTable';
import { listTenders, getUserDirectory } from '@/lib/data';

export const dynamic = 'force-dynamic';

interface SearchParams {
  q?: string;
  status?: string;
  priority?: string;
  owner?: string;
  deadline?: string;
  error?: string;
}

export default async function TendersPage({ searchParams }: { searchParams: SearchParams }) {
  const [rows, users] = await Promise.all([
    listTenders({
      q: searchParams.q,
      status: searchParams.status,
      priority: searchParams.priority,
      owner: searchParams.owner,
      deadline: searchParams.deadline,
    }),
    getUserDirectory(),
  ]);

  const red = rows.filter((r) => r.bid_due_date && new Date(r.bid_due_date) < new Date()).length;

  return (
    <>
      <div className="section-head">
        <div>
          <h1>Tenders</h1>
          <p className="subtitle">
            {rows.length} tender{rows.length === 1 ? '' : 's'} shown. Green = normal, Yellow =
            approaching deadline, Red = overdue or high risk.
          </p>
        </div>
        <Link className="btn" href="/tenders/new">
          + New tender
        </Link>
      </div>

      {searchParams.error && <div className="alert error">{searchParams.error}</div>}

      <div className="card">
        <TenderFilters
          values={{
            q: searchParams.q,
            status: searchParams.status,
            priority: searchParams.priority,
            owner: searchParams.owner,
            deadline: searchParams.deadline,
          }}
          users={users}
        />
      </div>

      <div className="card">
        <TenderTable rows={rows} />
      </div>
    </>
  );
}
