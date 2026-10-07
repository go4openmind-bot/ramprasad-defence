import { PGlite } from '@electric-sql/pglite';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const MIG = join(here, '..', 'migrations');
const SEED = join(here, '..', 'seed');
const SAMPLE = join(here, '..', 'sample_data.sql');

const db = new PGlite();
try {
  await db.exec(`create role anon nologin; create role authenticated nologin; create role service_role nologin bypassrls;`);

  for (const f of readdirSync(MIG).filter((f) => f.endsWith('.sql')).sort()) {
    await db.exec(readFileSync(join(MIG, f), 'utf8'));
  }
  for (const f of readdirSync(SEED).filter((f) => f.endsWith('.sql')).sort()) {
    await db.exec(readFileSync(join(SEED, f), 'utf8'));
  }

  // run twice to prove it is re-runnable (ON CONFLICT (id) DO NOTHING)
  await db.exec(readFileSync(SAMPLE, 'utf8'));
  await db.exec(readFileSync(SAMPLE, 'utf8'));

  const tables = ['customers','products','oems','tenders','tender_requirements','quotations','quotation_items','customer_orders','order_items','material_requirements','oem_rfqs','oem_quotations','purchase_orders','purchase_order_items','material_receipts','pdi_records','invoices','invoice_items','payments','warranties','tasks'];
  const counts = {};
  for (const t of tables) {
    counts[t] = (await db.query(`select count(*)::int n from public.${t}`)).rows[0].n;
  }
  console.log('sample_data.sql applied (twice, idempotent). Row counts:');
  console.log(JSON.stringify(counts, null, 0));

  const po1 = (await db.query(`select subtotal, grand_total from public.purchase_orders where po_no='PO-OEM-2001'`)).rows[0];
  const q2 = (await db.query(`select status, subtotal, grand_total, total_margin from public.quotations where quotation_no='QTN-0002'`)).rows[0];
  const inv2 = (await db.query(`select status from public.invoices where invoice_no='INV-2026-002'`)).rows[0];
  const po2 = (await db.query(`select actual_delivery_date from public.purchase_orders where po_no='PO-OEM-2002'`)).rows[0];
  console.log('PO-OEM-2001 totals:', JSON.stringify(po1));
  console.log('QTN-0002:', JSON.stringify(q2));
  console.log('INV-2026-002 status (should be partially_paid after the partial payment):', inv2.status);
  console.log('PO-OEM-2002 actual_delivery_date (from its receipt trigger):', po2.actual_delivery_date);
} catch (e) {
  console.log('SAMPLE FAILED: ' + e.message);
  process.exit(1);
}
