import Link from 'next/link';
import { canViewDashboard, computeTiles } from '@/lib/dashboard';
import { getCurrentContext } from '@/lib/data';

export const dynamic = 'force-dynamic';

export default async function DashboardPage() {
  const me = await getCurrentContext();

  if (!me || !canViewDashboard(me.roles)) {
    return (
      <>
        <h1>Management dashboard</h1>
        <div className="alert error">
          You do not have permission to view the management dashboard. It is available to
          management and administrators.
        </div>
        <Link href="/tenders">← Back to tenders</Link>
      </>
    );
  }

  const tiles = await computeTiles();

  return (
    <>
      <div className="section-head">
        <div>
          <h1>Management dashboard</h1>
          <p className="subtitle">
            {me.full_name} · every number links to the underlying records.
          </p>
        </div>
      </div>

      <div className="grid3">
        {tiles.map((tile) => (
          <Link key={tile.key} href={`/dashboard/${tile.key}`} className="card" style={{ textDecoration: 'none', color: 'inherit' }}>
            <h3 style={{ marginBottom: 6 }}>{tile.label}</h3>
            <div style={{ fontSize: 30, fontWeight: 700, lineHeight: 1.1 }}>
              {tile.value ?? tile.count}
            </div>
            <div className="hint" style={{ marginTop: 6 }}>
              {tile.value ? `${tile.count} record(s)` : 'record(s)'}
              {tile.note ? ` · ${tile.note}` : ''}
              {tile.color === 'red' ? ' · needs attention' : ''}
            </div>
            {tile.color && tile.color !== 'grey' && (
              <div style={{ marginTop: 8 }}>
                <span className={`badge ${tile.color}`}>
                  {tile.color === 'red' ? 'At risk' : tile.color === 'yellow' ? 'Watch' : 'Good'}
                </span>
              </div>
            )}
          </Link>
        ))}
      </div>
    </>
  );
}
