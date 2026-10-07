import Link from 'next/link';
import { requestPasswordReset } from '../login/actions';

export const dynamic = 'force-dynamic';

export default function ForgotPasswordPage({
  searchParams,
}: {
  searchParams: { error?: string; ok?: string };
}) {
  return (
    <div style={{ maxWidth: 420, margin: '40px auto' }}>
      <h1>Reset your password</h1>
      <p className="subtitle">Enter your email and we will send you a reset link.</p>

      {searchParams.error && <div className="alert error">{searchParams.error}</div>}
      {searchParams.ok && (
        <div className="alert info">
          If an account exists for that email, a reset link has been sent. Check your inbox (and spam).
        </div>
      )}

      <form action={requestPasswordReset} className="card stack">
        <div>
          <label htmlFor="email">Email</label>
          <input id="email" name="email" type="email" autoComplete="username" required />
        </div>
        <button className="btn" type="submit">
          Send reset link
        </button>
        <p className="small" style={{ margin: 0 }}>
          <Link href="/login">Back to sign in</Link>
        </p>
      </form>
    </div>
  );
}
