/**
 * Supabase connection test — prints only SUCCESS/FAILED, never any key.
 *
 * Usage (from the app/ folder), after filling app/.env.local:
 *   node --env-file=.env.local scripts/check-supabase.mjs
 */
import { createClient } from '@supabase/supabase-js';

const url = process.env.SUPABASE_URL;
const publishableKey = process.env.SUPABASE_PUBLISHABLE_KEY;

if (!url || !publishableKey) {
  console.log('FAILED: SUPABASE_URL and/or SUPABASE_PUBLISHABLE_KEY are not set.');
  console.log('Fill app/.env.local (see app/.env.example) and run again.');
  process.exit(2);
}

// Never print the key. Show only a non-reversible hint so you can confirm the
// right project/key is loaded without exposing anything usable.
console.log('Checking connection to configured Supabase project...');
console.log('  URL host: ' + new URL(url).host);
console.log('  Publishable key loaded: yes (value not shown)');

const supabase = createClient(url, publishableKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

try {
  const { error: authError } = await supabase.auth.getSession();
  if (authError) {
    console.log('FAILED: auth endpoint error: ' + authError.message);
    process.exit(1);
  }
  console.log('CONNECTIVITY: SUCCESS — reached the Supabase auth endpoint.');

  // A read against a Row Level Security protected table. Anonymous access
  // returns zero rows (no error) when RLS is working — that is healthy.
  // If the table does not exist, the schema has not been applied yet.
  const { data, error } = await supabase.from('roles').select('code').limit(1);
  if (error) {
    const msg = error.message || '';
    if (/could not find the table|does not exist|schema cache|relation/i.test(msg)) {
      console.log('SCHEMA: NOT APPLIED — table "public.roles" not found.');
      console.log('        Apply supabase/migrations (0001..0016) and supabase/seed to this project.');
      process.exit(0);
    }
    if (/permission denied/i.test(msg)) {
      console.log('SCHEMA: APPLIED — "public.roles" exists and anonymous access is correctly denied (grants + RLS).');
      console.log('        This is the expected, secure result: logged-out clients can read nothing.');
      process.exit(0);
    }
    console.log('FAILED: query error: ' + msg);
    process.exit(1);
  }

  console.log('SCHEMA: APPLIED — "public.roles" is reachable (rows returned: ' + (data?.length ?? 0) + '; 0 rows is normal for anonymous access under RLS).');
  process.exit(0);
} catch (e) {
  console.log('FAILED: ' + (e instanceof Error ? e.message : String(e)));
  process.exit(1);
}
