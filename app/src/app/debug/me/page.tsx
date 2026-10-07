import Link from 'next/link';
import { createClient } from '@/lib/supabase/server';
import { getCurrentContext } from '@/lib/data';

export const dynamic = 'force-dynamic';

/**
 * Read-only diagnostic for the signed-in user. Shows only information about
 * the current login (ids and roles) — never any key or secret.
 */
export default async function WhoAmIPage() {
  const supabase = createClient();
  const { data } = await supabase.auth.getUser();
  const user = data.user;

  if (!user) {
    return (
      <>
        <h1>Not signed in</h1>
        <p className="subtitle">Sign in first, then open this page again.</p>
        <Link href="/login">Go to sign in</Link>
      </>
    );
  }

  const me = await getCurrentContext();
  const { count: usersVisible } = await supabase.from('users').select('id', { count: 'exact', head: true });
  const { count: rolesVisible } = await supabase.from('user_roles').select('id', { count: 'exact', head: true });

  // Diagnostic only (local dev): record what this login resolves to, so the
  // developer can read it from the server log. No keys or secrets are logged.
  console.log(
    '[whoami] ' +
      JSON.stringify({
        authSub: user.id,
        usersRowFound: !!me,
        usersId: me?.id ?? null,
        roles: me?.roles ?? [],
        usersVisible: usersVisible ?? 0,
        rolesVisible: rolesVisible ?? 0,
      }),
  );

  return (
    <>
      <h1>Who am I (diagnostic)</h1>
      <p className="subtitle">This shows only your own login information.</p>

      <div className="card">
        <table>
          <tbody>
            <tr>
              <th>Auth email</th>
              <td>{user.email ?? '—'}</td>
            </tr>
            <tr>
              <th>Auth user id (JWT sub)</th>
              <td className="nowrap"><code>{user.id}</code></td>
            </tr>
            <tr>
              <th style={{ width: 260 }}>Matching public.users row</th>
              <td>
                {me ? (
                  <span className="badge green">found</span>
                ) : (
                  <span className="badge red">not found — this is the problem</span>
                )}
              </td>
            </tr>
            <tr>
              <th>Your internal users.id</th>
              <td className="nowrap">{me ? <code>{me.id}</code> : '—'}</td>
            </tr>
            <tr>
              <th>Your roles</th>
              <td>
                {me && me.roles.length > 0 ? (
                  me.roles.map((r) => (
                    <span key={r} className="chip" style={{ marginRight: 6 }}>{r}</span>
                  ))
                ) : (
                  <span className="badge red">none — so every insert is denied</span>
                )}
              </td>
            </tr>
            <tr>
              <th>users rows visible to you</th>
              <td>{usersVisible ?? 0}</td>
            </tr>
            <tr>
              <th>user_roles rows visible to you</th>
              <td>{rolesVisible ?? 0}</td>
            </tr>
          </tbody>
        </table>
      </div>

      <div className="card">
        <h3>What to do</h3>
        <ul>
          <li>If <strong>“Matching public.users row”</strong> is <em>not found</em>: run step 1 of the SQL in the chat (the
            <code> insert into public.users </code> using your auth user id).</li>
          <li>If the row is found but <strong>roles</strong> is <em>none</em>: run step 2 (the
            <code> insert into public.user_roles </code>).</li>
          <li>If <strong>roles</strong> shows <code>admin</code>, adding records should now work.</li>
        </ul>
      </div>
    </>
  );
}
