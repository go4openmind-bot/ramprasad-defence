/**
 * Server-only Supabase environment access.
 *
 * This module must only ever be imported by server-side code (server
 * components, server actions, route handlers, middleware). It is deliberately
 * NOT prefixed with NEXT_PUBLIC_, so these values are never inlined into
 * browser JavaScript.
 *
 * The Supabase *secret* (service_role) key is intentionally NOT read anywhere
 * in the application. Server-side operations use the publishable key and rely
 * on Row Level Security. If a trusted admin script ever needs the secret key,
 * read it from process.env.SUPABASE_SECRET_KEY inside that server-only script —
 * never here, and never in code that can reach the browser.
 */

if (typeof window !== 'undefined') {
  throw new Error('lib/supabase/env must only be imported from server-side code.');
}

/** Read the two values, trimming stray whitespace/newlines from pasted values. */
export function readSupabaseEnv(): { url?: string; publishableKey?: string } {
  return {
    url: process.env.SUPABASE_URL?.trim(),
    publishableKey: process.env.SUPABASE_PUBLISHABLE_KEY?.trim(),
  };
}

export interface SupabaseEnv {
  url: string;
  publishableKey: string;
}

/** True when both required variables are present (after trimming). */
export function isSupabaseConfigured(): boolean {
  const { url, publishableKey } = readSupabaseEnv();
  return Boolean(url && publishableKey);
}

/** Returns the URL and publishable key, or throws a secret-free error. */
export function getSupabaseEnv(): SupabaseEnv {
  const { url, publishableKey } = readSupabaseEnv();

  if (!url || !publishableKey) {
    throw new Error(
      'Supabase is not configured. Copy app/.env.example to app/.env.local and set SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY (see app/README.md).',
    );
  }

  try {
    // Validates the URL and rejects values with stray spaces/newlines.
    new URL(url);
  } catch {
    throw new Error('SUPABASE_URL is not a valid URL (check for spaces or a trailing newline).');
  }

  return { url, publishableKey };
}

/** Storage bucket for documents; defaults to "documents". */
export function getDocumentsBucket(): string {
  return (process.env.SUPABASE_DOCUMENTS_BUCKET || 'documents').trim() || 'documents';
}
