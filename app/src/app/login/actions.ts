'use server';

import { redirect } from 'next/navigation';
import { headers } from 'next/headers';
import { createClient } from '@/lib/supabase/server';

/** Only allow internal redirect targets (prevents open-redirect). */
function safeNext(value: string | null | undefined, fallback = '/tenders'): string {
  const v = (value ?? '').trim();
  return v.startsWith('/') && !v.startsWith('//') ? v : fallback;
}

export async function signIn(formData: FormData) {
  const email = String(formData.get('email') ?? '').trim();
  const password = String(formData.get('password') ?? '');
  const next = safeNext(String(formData.get('next') ?? ''));

  if (!email || !password) {
    redirect('/login?error=' + encodeURIComponent('Enter your email and password.'));
  }

  const supabase = createClient();
  const { error } = await supabase.auth.signInWithPassword({ email, password });

  if (error) {
    redirect('/login?error=' + encodeURIComponent('Sign-in failed: ' + error.message));
  }

  redirect(next);
}

export async function signOut() {
  const supabase = createClient();
  await supabase.auth.signOut();
  redirect('/login');
}

/** Send a password-reset email. Always redirects to the same "check your email" page
 *  so it never reveals whether an account exists. */
export async function requestPasswordReset(formData: FormData) {
  const email = String(formData.get('email') ?? '').trim();
  if (!email) {
    redirect('/forgot-password?error=' + encodeURIComponent('Enter your email address.'));
  }

  const h = headers();
  const host = h.get('x-forwarded-host') ?? h.get('host') ?? 'localhost:3000';
  const proto = h.get('x-forwarded-proto') ?? (host.startsWith('localhost') ? 'http' : 'https');
  const origin = `${proto}://${host}`;

  const supabase = createClient();
  await supabase.auth.resetPasswordForEmail(email, {
    redirectTo: `${origin}/auth/callback`,
  });

  redirect('/forgot-password?ok=1');
}

/** Set a new password for the signed-in user (arrived from the reset email link). */
export async function updatePassword(formData: FormData) {
  const password = String(formData.get('password') ?? '');
  const confirm = String(formData.get('confirm') ?? '');

  if (password.length < 8) {
    redirect('/reset-password?error=' + encodeURIComponent('Password must be at least 8 characters.'));
  }
  if (password !== confirm) {
    redirect('/reset-password?error=' + encodeURIComponent('The two passwords do not match.'));
  }

  const supabase = createClient();
  const { error } = await supabase.auth.updateUser({ password });

  if (error) {
    redirect('/reset-password?error=' + encodeURIComponent('Could not update password: ' + error.message));
  }

  redirect('/login?ok=reset');
}
