import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const db = new PGlite();

try {
  await db.exec(`create role anon nologin; create role authenticated nologin; create role service_role nologin bypassrls;`);
  await db.exec(readFileSync(join(here, '..', 'combined_setup.sql'), 'utf8'));
  const t = (await db.query(`select count(*)::int n from information_schema.tables where table_schema='public' and table_type='BASE TABLE'`)).rows[0].n;
  const r = (await db.query(`select count(*)::int n from public.roles`)).rows[0].n;
  console.log('combined_setup.sql executed OK: tables=' + t + ' roles=' + r);
} catch (e) {
  console.log('COMBINED FAILED: ' + e.message);
  process.exit(1);
}
