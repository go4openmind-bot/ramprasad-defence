import Link from 'next/link';
import { signIn } from './actions';
import { isSupabaseConfigured } from '@/lib/supabase/env';

export const dynamic = 'force-dynamic';

export default function LoginPage({
  searchParams,
}: {
  searchParams: { error?: string; next?: string; ok?: string };
}) {
  const configured = isSupabaseConfigured();

  return (
    <div style={{ maxWidth: 420, margin: '40px auto' }}>
      <h1>Sign in</h1>
      <p className="subtitle">Use the email and password given to you by the administrator.</p>

      {!configured && (
        <div className="alert error">
          The app is not connected to Supabase yet. Copy <code>app/.env.example</code> to{' '}
          <code>app/.env.local</code> and set <code>SUPABASE_URL</code> and{' '}
          <code>SUPABASE_PUBLISHABLE_KEY</code>.
        </div>
      )}

      {searchParams.error && <div className="alert error">{searchParams.error}</div>}
      {searchParams.ok === 'reset' && (
        <div className="alert info">Your password has been updated. Please sign in.</div>
      )}

      <form action={signIn} className="card stack">
        <input type="hidden" name="next" value={searchParams.next ?? '/tenders'} />
        <div>
          <label htmlFor="email">Email</label>
          <input id="email" name="email" type="email" autoComplete="username" required />
        </div>
        <div>
          <label htmlFor="password">Password</label>
          <input id="password" name="password" type="password" autoComplete="current-password" required />
        </div>
        <button className="btn" type="submit" disabled={!configured}>
          Sign in
        </button>
        <p className="small" style={{ margin: 0 }}>
          <Link href="/forgot-password">Forgot your password?</Link>
        </p>
      </form>
    </div>
  );
}
