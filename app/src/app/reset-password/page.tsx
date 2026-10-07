import Link from 'next/link';
import { updatePassword } from '../login/actions';
import { isSupabaseConfigured } from '@/lib/supabase/env';
import { getCurrentUser } from '@/lib/supabase/server';

export const dynamic = 'force-dynamic';

export default async function ResetPasswordPage({
  searchParams,
}: {
  searchParams: { error?: string };
}) {
  const configured = isSupabaseConfigured();
  const user = configured ? await getCurrentUser() : null;

  if (!user) {
    return (
      <div style={{ maxWidth: 420, margin: '40px auto' }}>
        <h1>Reset password</h1>
        <div className="alert error">
          This password reset link is invalid or has expired. Please request a new one.
        </div>
        <p className="small">
          <Link href="/forgot-password">Request a new reset link</Link> · <Link href="/login">Back to sign in</Link>
        </p>
      </div>
    );
  }

  return (
    <div style={{ maxWidth: 420, margin: '40px auto' }}>
      <h1>Set a new password</h1>
      <p className="subtitle">Signed in as {user.email ?? '—'}.</p>

      {searchParams.error && <div className="alert error">{searchParams.error}</div>}

      <form action={updatePassword} className="card stack">
        <div>
          <label htmlFor="password">New password</label>
          <input id="password" name="password" type="password" autoComplete="new-password" minLength={8} required />
          <div className="hint">At least 8 characters.</div>
        </div>
        <div>
          <label htmlFor="confirm">Confirm new password</label>
          <input id="confirm" name="confirm" type="password" autoComplete="new-password" minLength={8} required />
        </div>
        <button className="btn" type="submit">
          Update password
        </button>
      </form>
    </div>
  );
}
