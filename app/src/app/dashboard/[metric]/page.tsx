import Link from 'next/link';
import { canViewDashboard, loadDrill } from '@/lib/dashboard';
import { getCurrentContext } from '@/lib/data';

export const dynamic = 'force-dynamic';

export default async function DashboardDrillPage({ params }: { params: { metric: string } }) {
  const me = await getCurrentContext();

  if (!me || !canViewDashboard(me.roles)) {
    return (
      <>
        <h1>Management dashboard</h1>
        <div className="alert error">
          You do not have permission to view this page. It is available to management and
          administrators.
        </div>
        <Link href="/tenders">← Back to tenders</Link>
      </>
    );
  }

  const drill = await loadDrill(params.metric);
  if (!drill) {
    return (
      <>
        <h1>Unknown dashboard metric</h1>
        <Link href="/dashboard">← Back to dashboard</Link>
      </>
    );
  }

  return (
    <>
      <div className="section-head">
        <div>
          <h1>{drill.title}</h1>
          {drill.subtitle && <p className="subtitle">{drill.subtitle}</p>}
        </div>
        <Link className="btn secondary" href="/dashboard">← Dashboard</Link>
      </div>

      {drill.summary && drill.summary.length > 0 && (
        <div className="grid2">
          {drill.summary.map((s) => (
            <div key={s.label} className="card">
              <h3>{s.label}</h3>
              <p style={{ fontSize: 24, margin: 0 }}>{s.value}</p>
            </div>
          ))}
        </div>
      )}

      <div className="card">
        {drill.rows.length === 0 ? (
          <p className="empty">No records for this metric.</p>
        ) : (
          <div style={{ overflowX: 'auto' }}>
            <table>
              <thead>
                <tr>
                  {drill.columns.map((c) => (
                    <th key={c.key} className="nowrap">{c.label}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {drill.rows.map((row, idx) => (
                  <tr key={idx}>
                    {drill.columns.map((c, ci) => (
                      <td key={c.key} className={ci === 0 ? 'nowrap' : undefined}>
                        {ci === 0 && row.href ? (
                          <Link href={row.href}>{row.cells[c.key] ?? '—'}</Link>
                        ) : (
                          row.cells[c.key] ?? '—'
                        )}
                      </td>
                    ))}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      <p className="hint">
        Showing {drill.rows.length} record(s). Figures are from the data your login is permitted
        to see (Row Level Security).
      </p>
    </>
  );
}
