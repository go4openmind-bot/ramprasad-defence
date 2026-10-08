import { getSupabaseEnv, isSupabaseConfigured, readSupabaseEnv } from '@/lib/supabase/env';

export const dynamic = 'force-dynamic';

/**
 * Environment diagnostic. Shows whether the deployment's environment variables
 * loaded and their shape (length / prefix) so a bad paste can be spotted.
 * It never shows a full key.
 */
export default function DebugEnvPage() {
  const { url, publishableKey } = readSupabaseEnv();

  let host = '';
  let urlValid = false;
  try {
    host = new URL(url ?? '').host;
    urlValid = true;
  } catch {
    urlValid = false;
  }

  let envError = '';
  try {
    getSupabaseEnv();
  } catch (e) {
    envError = e instanceof Error ? e.message : String(e);
  }

  return (
    <>
      <h1>Environment diagnostic</h1>
      <p className="subtitle">Shape of the environment variables this deployment loaded (no full key shown).</p>

      <div className="card">
        <table>
          <tbody>
            <tr>
              <th style={{ width: 280 }}>Configured (both present)</th>
              <td>{isSupabaseConfigured() ? <span className="badge green">yes</span> : <span className="badge red">no</span>}</td>
            </tr>
            <tr>
              <th>SUPABASE_URL present</th>
              <td>{url ? 'yes' : 'no'}</td>
            </tr>
            <tr>
              <th>SUPABASE_URL valid</th>
              <td>{urlValid ? <span className="badge green">yes</span> : <span className="badge red">no</span>}</td>
            </tr>
            <tr>
              <th>SUPABASE_URL host</th>
              <td className="nowrap">{host || '—'}</td>
            </tr>
            <tr>
              <th>SUPABASE_URL length</th>
              <td>{url ? url.length : 0} <span className="hint">(expected 40; 41+ means a stray space/newline)</span></td>
            </tr>
            <tr>
              <th>PUBLISHABLE key present</th>
              <td>{publishableKey ? 'yes' : 'no'}</td>
            </tr>
            <tr>
              <th>PUBLISHABLE key length</th>
              <td>{publishableKey ? publishableKey.length : 0} <span className="hint">(expected 46)</span></td>
            </tr>
            <tr>
              <th>PUBLISHABLE key prefix</th>
              <td className="nowrap"><code>{publishableKey ? publishableKey.slice(0, 14) + '…' : '—'}</code> <span className="hint">(should start sb_publishable_)</span></td>
            </tr>
            <tr>
              <th>Load error</th>
              <td>{envError ? <span className="badge red">{envError}</span> : 'none'}</td>
            </tr>
          </tbody>
        </table>
      </div>

      <p className="hint">
        If lengths differ from expected, the value has extra characters — re-add it in Vercel by pasting again.
      </p>
    </>
  );
}
