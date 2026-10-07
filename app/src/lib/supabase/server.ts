import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';
import { getSupabaseEnv } from './env';

/**
 * Server-side Supabase client. Uses the publishable (anon) key plus the
 * signed-in user's session cookie; every query is still filtered by Row Level
 * Security in the database. The service/secret key is never used here.
 */
export function createClient() {
  const cookieStore = cookies();
  const { url, publishableKey } = getSupabaseEnv();

  return createServerClient(url, publishableKey, {
    cookies: {
      getAll() {
        return cookieStore.getAll();
      },
      setAll(cookiesToSet) {
        try {
          cookiesToSet.forEach(({ name, value, options }) => cookieStore.set(name, value, options));
        } catch {
          // Called from a Server Component: cookie writes are handled by middleware.
        }
      },
    },
  });
}

/** Current signed-in user, or null. */
export async function getCurrentUser() {
  const supabase = createClient();
  const { data } = await supabase.auth.getUser();
  return data.user ?? null;
}
