/**
 * validate.mjs — schema + security acceptance test for the Ramprasad Defence database.
 *
 * Runs every file in ../migrations in filename order and every file in ../seed,
 * against PGlite (real PostgreSQL compiled to WASM — no Docker or server needed),
 * then executes 32 checks covering constraints, RLS, triggers, the PDI gate,
 * segregation of duties, the invoice lock and append-only audit.
 *
 * Run:
 *   cd supabase/tests
 *   npm install
 *   npm test
 *
 * Exit code 0 = all checks passed. Non-zero = at least one failed (see output).
 */
import { PGlite } from '@electric-sql/pglite';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const MIG = join(here, '..', 'migrations');
const SEED = join(here, '..', 'seed');

const db = new PGlite();
const lines = [];
const log = (s) => { lines.push(s); };
let pass = 0, fail = 0;
function check(name, cond, detail) {
  if (cond) { pass++; log('PASS  ' + name); }
  else { fail++; log('FAIL  ' + name + ' :: ' + (detail ?? '')); }
}
async function runAs(role, sub, sql) {
  await db.exec(`reset role`);
  if (role) await db.exec(`set role ${role}`);
  await db.exec(`set request.jwt.claims = '${JSON.stringify({ sub: sub ?? null })}'`);
  try { await db.exec(sql); } finally { await db.exec(`reset role`); }
}
async function queryAs(role, sub, sql) {
  await db.exec(`reset role`);
  if (role) await db.exec(`set role ${role}`);
  await db.exec(`set request.jwt.claims = '${JSON.stringify({ sub: sub ?? null })}'`);
  try { return await db.query(sql); } finally { await db.exec(`reset role`); }
}
async function expectError(name, role, sub, sql, needle) {
  try {
    await runAs(role, sub, sql);
    check(name, false, 'expected an error but the statement succeeded');
  } catch (e) {
    const ok = needle ? e.message.toLowerCase().includes(needle.toLowerCase()) : true;
    check(name, ok, 'got: ' + e.message);
  }
}

const U = {
  admin:       '00000000-0000-0000-0000-0000000000a1',
  management:  '00000000-0000-0000-0000-0000000000a2',
  sales:       '00000000-0000-0000-0000-0000000000a3',
  technical:   '00000000-0000-0000-0000-0000000000a4',
  procurement: '00000000-0000-0000-0000-0000000000a5',
  stores:      '00000000-0000-0000-0000-0000000000a6',
  qa:          '00000000-0000-0000-0000-0000000000a7',
  logistics:   '00000000-0000-0000-0000-0000000000a8',
  accounts:    '00000000-0000-0000-0000-0000000000a9',
  viewer:      '00000000-0000-0000-0000-0000000000b0',
};

try {
  await db.exec(`create role anon nologin; create role authenticated nologin; create role service_role nologin bypassrls;`);

  const files = readdirSync(MIG).filter(f => f.endsWith('.sql')).sort();
  for (const f of files) {
    try { await db.exec(readFileSync(join(MIG, f), 'utf8')); log('applied ' + f); }
    catch (e) { log('MIGRATION FAILED ' + f + ' :: ' + e.message); throw e; }
  }
  for (const f of readdirSync(SEED).filter(f => f.endsWith('.sql')).sort()) {
    await db.exec(readFileSync(join(SEED, f), 'utf8')); log('seeded ' + f);
  }

  const tcount = (await db.query(`select count(*)::int n from information_schema.tables where table_schema='public' and table_type='BASE TABLE'`)).rows[0].n;
  check('schema: 41+ business tables exist', tcount >= 41, 'found ' + tcount);
  const rcount = (await db.query(`select count(*)::int n from public.roles`)).rows[0].n;
  check('seed: 10 roles', rcount === 10, 'found ' + rcount);
  const rlsOn = (await db.query(`select count(*)::int n from pg_tables where schemaname='public' and rowsecurity=true and tablename<>'audit_logs'`)).rows[0].n;
  check('RLS enabled on all business tables', rlsOn >= 40, 'found ' + rlsOn);

  for (const [role, id] of Object.entries(U)) {
    await db.exec(`insert into public.users(id, auth_user_id, full_name, email) values ('${id}','${id}','${role} user','${role}@example.test')`);
    await db.exec(`insert into public.user_roles(user_id, role_code) values ('${id}','${role}')`);
  }
  log('seeded ' + Object.keys(U).length + ' test users');

  await db.exec(`insert into public.customers(id, code, name) values ('10000000-0000-0000-0000-000000000001','CUST1','Indian Army')`);
  await db.exec(`insert into public.products(id, code, name, unit) values ('20000000-0000-0000-0000-000000000001','PRD1','Radio Set','NO')`);
  await db.exec(`insert into public.oems(id, code, name) values ('30000000-0000-0000-0000-000000000001','OEM1','Bharat Electronics')`);

  await expectError('constraint: tender bid_due before received is rejected', null, null,
    `insert into public.tenders(tender_no, customer_id, title, received_date, bid_due_date) values ('T-BAD','10000000-0000-0000-0000-000000000001','bad','2026-10-10','2026-10-01')`,
    'tenders_due_after_received_chk');
  await expectError('constraint: tender_requirement quantity 0 is rejected', null, null,
    `insert into public.tenders(tender_no, customer_id, title, received_date) values ('T-REQ','10000000-0000-0000-0000-000000000001','req test','2026-10-01');
     insert into public.tender_requirements(tender_id, line_no, description, quantity, unit)
     select id, 1, 'zero qty', 0, 'NO' from public.tenders where tender_no='T-REQ'`,
    'tender_requirements_qty_chk');

  // --- tender workflow (0014): 13-stage status pipeline + notes ---
  await expectError('workflow: unknown tender status is rejected', null, null,
    `insert into public.tenders(tender_no, customer_id, title, received_date, status) values ('T-STATUS','10000000-0000-0000-0000-000000000001','bad status','2026-10-01','bogus')`,
    'tenders_status_chk');
  await db.exec(`insert into public.tenders(tender_no, customer_id, title, received_date, status) values ('T-NOTE','10000000-0000-0000-0000-000000000001','note test','2026-10-01','under_review')`);
  const st = (await db.query(`select status from public.tenders where tender_no='T-NOTE'`)).rows[0].status;
  check('workflow: valid pipeline status accepted', st === 'under_review', 'got ' + st);
  await runAs('authenticated', U.sales,
    `insert into public.tender_notes(tender_id, note) select id, 'first note' from public.tenders where tender_no='T-NOTE'`)
    .then(() => check('notes: sales can add a tender note', true))
    .catch((e) => check('notes: sales can add a tender note', false, e.message));
  await expectError('notes: viewer cannot add a tender note', 'authenticated', U.viewer,
    `insert into public.tender_notes(tender_id, note) select id, 'viewer note' from public.tenders where tender_no='T-NOTE'`,
    'row-level security');
  const noteCount = (await queryAs('authenticated', U.viewer, `select count(*)::int n from public.tender_notes`)).rows[0].n;
  check('notes: staff can read tender notes', noteCount >= 1, 'saw ' + noteCount);

  await db.exec(`
    insert into public.quotations(id, quotation_no, version, customer_id, quote_date)
      values ('40000000-0000-0000-0000-000000000001','Q-1',1,'10000000-0000-0000-0000-000000000001','2026-10-01');
    insert into public.quotation_items(quotation_id, line_no, description, quantity, unit_price, discount_pct, tax_pct)
      values ('40000000-0000-0000-0000-000000000001',1,'Radio',2,100,10,18),
             ('40000000-0000-0000-0000-000000000001',2,'Antenna',1,50,0,18);
  `);
  const li = (await db.query(`select line_total from public.quotation_items where quotation_id='40000000-0000-0000-0000-000000000001' and line_no=1`)).rows[0].line_total;
  check('generated: line_total = 2*100*0.9*1.18 = 212.40', Number(li) === 212.4, 'got ' + li);
  const q = (await db.query(`select subtotal, tax_total, grand_total from public.quotations where id='40000000-0000-0000-0000-000000000001'`)).rows[0];
  check('trigger: quotation subtotal = 230.00', Number(q.subtotal) === 230, 'got ' + q.subtotal);
  check('trigger: quotation grand_total = 271.40', Number(q.grand_total) === 271.4, 'got ' + q.grand_total);
  check('trigger: quotation tax_total = grand - subtotal = 41.40', Number(q.tax_total) === 41.4, 'got ' + q.tax_total);

  // --- quotation module (0015): cost, margin, compliance, immutability, revision ---
  await db.exec(`update public.quotation_items
                    set purchase_unit_cost=40, logistics_unit_cost=5, other_unit_cost=5, technical_compliance='compliant'
                  where quotation_id='40000000-0000-0000-0000-000000000001' and line_no=1`);
  const li2 = (await db.query(`select line_base, line_cost, line_margin, line_margin_pct
                                 from public.quotation_items
                                where quotation_id='40000000-0000-0000-0000-000000000001' and line_no=1`)).rows[0];
  check('quotation: line margin = 80.00', Number(li2.line_margin) === 80, JSON.stringify(li2));
  check('quotation: line margin % = 44.44', Number(li2.line_margin_pct) === 44.44, String(li2.line_margin_pct));
  const qm = (await db.query(`select total_purchase_cost, total_logistics_cost, total_other_cost, total_margin
                                from public.quotations where id='40000000-0000-0000-0000-000000000001'`)).rows[0];
  check('quotation: header costs + margin', Number(qm.total_purchase_cost) === 80
    && Number(qm.total_logistics_cost) === 10 && Number(qm.total_other_cost) === 10
    && Number(qm.total_margin) === 130, JSON.stringify(qm));

  await expectError('quotation: invalid technical compliance rejected', null, null,
    `update public.quotation_items set technical_compliance='bogus'
      where quotation_id='40000000-0000-0000-0000-000000000001'`,
    'quotation_items_tech_compliance_chk');

  await db.exec(`update public.quotations set status='approved', approved_by='${U.management}', approved_at=now()
                  where id='40000000-0000-0000-0000-000000000001'`);
  await expectError('quotation: approved header cannot be edited', null, null,
    `update public.quotations set payment_terms='Net 30'
      where id='40000000-0000-0000-0000-000000000001'`,
    'create a revision');
  await expectError('quotation: approved lines cannot be changed', null, null,
    `insert into public.quotation_items(quotation_id, line_no, description, quantity, unit_price)
     values ('40000000-0000-0000-0000-000000000001',3,'extra',1,10)`,
    'create a revision');

  await db.exec(`insert into public.quotations(quotation_no, version, customer_id, quote_date, revision_of, status)
                 values ('Q-1', 2, '10000000-0000-0000-0000-000000000001', '2026-10-07',
                         '40000000-0000-0000-0000-000000000001', 'draft')`);
  const rev = (await db.query(`select version, revision_of from public.quotations where quotation_no='Q-1' order by version`)).rows;
  check('quotation: revision is a new v2 row linked to v1', rev.length === 2 && rev[1].version === 2
    && rev[1].revision_of === '40000000-0000-0000-0000-000000000001', JSON.stringify(rev));
  await db.exec(`update public.quotations set status='revised' where id='40000000-0000-0000-0000-000000000001'`);
  const oldStatus = (await db.query(`select status from public.quotations where id='40000000-0000-0000-0000-000000000001'`)).rows[0].status;
  check('quotation: previous version may be marked revised (status change allowed)', oldStatus === 'revised', oldStatus);

  // --- procurement module (0016) ---
  await db.exec(`insert into public.material_requirements(id, requirement_no, required_by_date, status)
                 values ('c0000000-0000-0000-0000-000000000001','MR-1','2026-11-01','open')`);
  await db.exec(`insert into public.material_requirement_items(material_requirement_id, line_no, description, quantity, unit)
                 values ('c0000000-0000-0000-0000-000000000001',1,'Radio Set',10,'NO')`);
  await expectError('procurement: material requirement qty 0 rejected', null, null,
    `insert into public.material_requirement_items(material_requirement_id, line_no, description, quantity)
     values ('c0000000-0000-0000-0000-000000000001',2,'bad',0)`,
    'material_requirement_items_qty_chk');

  await db.exec(`insert into public.oem_quotations(id, quotation_no, oem_id, quote_date, currency)
                 values ('c1000000-0000-0000-0000-000000000001','OEMQ-1','30000000-0000-0000-0000-000000000001','2026-10-01','INR')`);
  await db.exec(`insert into public.oem_quotation_items(oem_quotation_id, line_no, description, quantity, unit, unit_price, tax_pct)
                 values ('c1000000-0000-0000-0000-000000000001',1,'Radio Set',2,'NO',100,18)`);
  const oq = (await db.query(`select subtotal, tax_total, grand_total from public.oem_quotations where id='c1000000-0000-0000-0000-000000000001'`)).rows[0];
  check('procurement: OEM quotation totals (200 / 36 / 236)',
    Number(oq.subtotal) === 200 && Number(oq.tax_total) === 36 && Number(oq.grand_total) === 236,
    JSON.stringify(oq));

  await db.exec(`insert into public.purchase_orders(id, po_no, oem_id, status)
                 values ('c2000000-0000-0000-0000-000000000001','PO-PROC-1','30000000-0000-0000-0000-000000000001','pending_approval')`);
  await db.exec(`insert into public.purchase_approvals(purchase_order_id, step_no, decision)
                 values ('c2000000-0000-0000-0000-000000000001',1,'approved')`);
  await expectError('procurement: cannot approve the same PO twice', null, null,
    `insert into public.purchase_approvals(purchase_order_id, step_no, decision)
     values ('c2000000-0000-0000-0000-000000000001',2,'approved')`,
    'purchase_approvals_one_approved_idx');

  await db.exec(`insert into public.documents(id, file_name, storage_path, classification)
                 values ('c3000000-0000-0000-0000-000000000001','cert.pdf','proc/cert.pdf','internal')`);
  const docId = 'c3000000-0000-0000-0000-000000000001';
  await db.exec(`insert into public.procurement_documents(entity_type, entity_id, document_id, doc_type)
                 values ('purchase_order','c2000000-0000-0000-0000-000000000001','${docId}','compliance_certificate')`);
  await expectError('procurement: duplicate compliance document link rejected', null, null,
    `insert into public.procurement_documents(entity_type, entity_id, document_id, doc_type)
     values ('purchase_order','c2000000-0000-0000-0000-000000000001','${docId}','other')`,
    'procurement_documents_unique');

  await db.exec(`insert into public.material_receipts(grn_no, purchase_order_id, oem_id, received_date, status)
                 values ('GRN-PROC-1','c2000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','2026-10-20','received')`);
  const adOk = (await db.query(`select (actual_delivery_date = date '2026-10-20') as ok
                                  from public.purchase_orders where id='c2000000-0000-0000-0000-000000000001'`)).rows[0].ok;
  check('procurement: actual delivery date set from receipt', adOk === true, String(adOk));

  // remove the test document so later document-visibility counts stay exact
  await db.exec(`delete from public.documents where id = 'c3000000-0000-0000-0000-000000000001'`);



  const noUser = (await queryAs('authenticated', null, `select count(*)::int n from public.tenders`)).rows[0].n;
  check('RLS: authenticated-but-no-user sees 0 tenders', noUser === 0, 'saw ' + noUser);
  await runAs('authenticated', U.viewer, `insert into public.customers(code,name) values ('V1','viewer attempt')`)
    .then(() => check('RLS: viewer cannot insert customer', false, 'insert succeeded'))
    .catch((e) => check('RLS: viewer cannot insert customer', e.message.toLowerCase().includes('row-level security'), e.message));
  await runAs('authenticated', U.sales, `insert into public.tenders(tender_no, customer_id, title, received_date, bid_due_date) values ('T-RLS','10000000-0000-0000-0000-000000000001','rls ok','2026-10-01','2026-10-20')`)
    .then(() => check('RLS: sales can insert tender', true))
    .catch((e) => check('RLS: sales can insert tender', false, e.message));
  await expectError('RLS: accounts cannot insert purchase order', 'authenticated', U.accounts,
    `insert into public.purchase_orders(po_no, oem_id) values ('PO-DENY','30000000-0000-0000-0000-000000000001')`,
    'row-level security');
  const viewerRead = (await queryAs('authenticated', U.viewer, `select count(*)::int n from public.tenders`)).rows[0].n;
  check('RLS: viewer can read tenders', viewerRead >= 1, 'saw ' + viewerRead);

  await db.exec(`insert into public.documents(id, file_name, storage_path, classification, entity_table) values
    ('50000000-0000-0000-0000-000000000001','public.pdf','t/pub.pdf','internal','tenders'),
    ('50000000-0000-0000-0000-000000000002','secret.pdf','t/secret.pdf','controlled','tenders')`);
  const logiDocs = (await queryAs('authenticated', U.logistics, `select count(*)::int n from public.documents`)).rows[0].n;
  const techDocs = (await queryAs('authenticated', U.technical, `select count(*)::int n from public.documents`)).rows[0].n;
  check('RLS: logistics sees only non-controlled documents (1)', logiDocs === 1, 'saw ' + logiDocs);
  check('RLS: technical sees controlled documents too (2)', techDocs === 2, 'saw ' + techDocs);

  const auditBefore = (await db.query(`select count(*)::int n from public.audit_logs`)).rows[0].n;
  await runAs('authenticated', U.sales, `insert into public.customers(code,name) values ('AUD1','audit test')`);
  const auditAfter = (await db.query(`select count(*)::int n from public.audit_logs where entity_table='customers' and action='insert'`)).rows[0].n;
  check('audit: insert wrote an audit_logs row', auditAfter >= 1, 'before ' + auditBefore + ' after ' + auditAfter);

  const before = (await db.query(`select updated_at from public.customers where code='AUD1'`)).rows[0].updated_at;
  await new Promise(r => setTimeout(r, 20));
  await db.exec(`update public.customers set name='audit test 2' where code='AUD1'`);
  const after = (await db.query(`select updated_at from public.customers where code='AUD1'`)).rows[0].updated_at;
  check('trigger: updated_at changes on update', new Date(after) > new Date(before), before + ' -> ' + after);

  const auditCountBefore = (await db.query(`select count(*)::int n from public.audit_logs`)).rows[0].n;
  await runAs('authenticated', U.admin, `delete from public.audit_logs`);
  const auditCountAfter = (await db.query(`select count(*)::int n from public.audit_logs`)).rows[0].n;
  check('audit append-only: admin delete removed 0 audit rows', auditCountAfter === auditCountBefore, 'before ' + auditCountBefore + ' after ' + auditCountAfter);
  await expectError('RLS: no insert policy lets a normal user forge audit rows', 'authenticated', U.admin,
    `insert into public.audit_logs(action, entity_table) values ('insert','customers')`, 'row-level security');

  await db.exec(`
    insert into public.customer_orders(id, order_no, customer_id, status)
      values ('60000000-0000-0000-0000-000000000001','PO-CUST-1','10000000-0000-0000-0000-000000000001','received');
    insert into public.order_items(id, customer_order_id, line_no, product_id, description, quantity, unit, unit_price, tax_pct)
      values ('61000000-0000-0000-0000-000000000001','60000000-0000-0000-0000-000000000001',1,'20000000-0000-0000-0000-000000000001','Radio Set',10,'NO',1000,18);
    insert into public.purchase_orders(id, po_no, oem_id, customer_order_id, status)
      values ('70000000-0000-0000-0000-000000000001','PO-OEM-1','30000000-0000-0000-0000-000000000001','60000000-0000-0000-0000-000000000001','sent');
    insert into public.purchase_order_items(id, purchase_order_id, line_no, product_id, order_item_id, description, quantity, unit, unit_price, tax_pct)
      values ('71000000-0000-0000-0000-000000000001','70000000-0000-0000-0000-000000000001',1,'20000000-0000-0000-0000-000000000001','61000000-0000-0000-0000-000000000001','Radio Set',10,'NO',700,18);
  `);
  await db.exec(`update public.purchase_orders set created_by='${U.procurement}' where id='70000000-0000-0000-0000-000000000001'`);
  await db.exec(`insert into public.material_receipts(id, grn_no, purchase_order_id, oem_id, received_date, status, received_by)
                 values ('80000000-0000-0000-0000-000000000001','GRN-1','70000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','2026-10-05','received','${U.stores}')`);
  await db.exec(`insert into public.material_receipt_items(material_receipt_id, purchase_order_item_id, product_id, qty_received, qty_accepted)
                 values ('80000000-0000-0000-0000-000000000001','71000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001',10,10)`);
  const recv = (await db.query(`select received_qty, status from public.purchase_order_items where id='71000000-0000-0000-0000-000000000001'`)).rows[0];
  check('trigger: received_qty = 10 after receipt', Number(recv.received_qty) === 10, JSON.stringify(recv));
  check('trigger: PO line status = received', recv.status === 'received', recv.status);

  await db.exec(`insert into public.dispatches(id, dispatch_no, customer_order_id, customer_id, status)
                 values ('90000000-0000-0000-0000-000000000001','DSP-1','60000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','prepared')`);
  await expectError('PDI gate: dispatch blocked before any passed PDI', 'authenticated', U.logistics,
    `insert into public.dispatch_items(dispatch_id, order_item_id, product_id, quantity)
     values ('90000000-0000-0000-0000-000000000001','61000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001',5)`,
    'passed pdi');
  await db.exec(`insert into public.pdi_records(id, pdi_no, customer_order_id, inspection_type, result, created_by)
                 values ('a0000000-0000-0000-0000-000000000001','PDI-FAIL','60000000-0000-0000-0000-000000000001','pdi','fail','${U.qa}')`);
  await db.exec(`insert into public.pdi_items(pdi_record_id, material_receipt_item_id, product_id, qty_inspected, qty_failed)
                 values ('a0000000-0000-0000-0000-000000000001',(select id from public.material_receipt_items limit 1),'20000000-0000-0000-0000-000000000001',10,10)`);
  await expectError('PDI gate: dispatch still blocked on failed PDI', 'authenticated', U.logistics,
    `insert into public.dispatch_items(dispatch_id, order_item_id, product_id, quantity)
     values ('90000000-0000-0000-0000-000000000001','61000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001',5)`,
    'passed pdi');
  await db.exec(`insert into public.pdi_records(id, pdi_no, customer_order_id, inspection_type, result, created_by)
                 values ('a0000000-0000-0000-0000-000000000002','PDI-PASS','60000000-0000-0000-0000-000000000001','pdi','pass','${U.qa}')`);
  await db.exec(`insert into public.pdi_items(pdi_record_id, material_receipt_item_id, product_id, qty_inspected, qty_passed)
                 values ('a0000000-0000-0000-0000-000000000002',(select id from public.material_receipt_items limit 1),'20000000-0000-0000-0000-000000000001',10,10)`);
  await runAs('authenticated', U.logistics,
    `insert into public.dispatch_items(dispatch_id, order_item_id, product_id, quantity)
     values ('90000000-0000-0000-0000-000000000001','61000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001',5)`)
    .then(() => check('PDI gate: dispatch allowed after passed PDI', true))
    .catch((e) => check('PDI gate: dispatch allowed after passed PDI', false, e.message));
  const deliv = (await db.query(`select delivered_qty, status from public.order_items where id='61000000-0000-0000-0000-000000000001'`)).rows[0];
  check('trigger: delivered_qty = 5 after dispatch', Number(deliv.delivered_qty) === 5, JSON.stringify(deliv));
  check('trigger: order line status = partially_delivered', deliv.status === 'partially_delivered', deliv.status);

  await db.exec(`insert into public.invoices(id, invoice_no, customer_id, customer_order_id, status, created_by)
                 values ('b0000000-0000-0000-0000-000000000001','INV-1','10000000-0000-0000-0000-000000000001','60000000-0000-0000-0000-000000000001','issued','${U.accounts}')`);
  await db.exec(`insert into public.invoice_items(invoice_id, line_no, product_id, description, quantity, unit, unit_price, tax_pct)
                 values ('b0000000-0000-0000-0000-000000000001',1,'20000000-0000-0000-0000-000000000001','Radio Set',5,'NO',1000,18)`);
  const inv = (await db.query(`select grand_total from public.invoices where id='b0000000-0000-0000-0000-000000000001'`)).rows[0];
  check('trigger: invoice grand_total = 5900.00', Number(inv.grand_total) === 5900, 'got ' + inv.grand_total);
  await expectError('segregation: invoice creator cannot record its payment', 'authenticated', U.accounts,
    `insert into public.payments(payment_no, payment_type, invoice_id, amount, reference)
     values ('PMT-DENY','customer_receipt','b0000000-0000-0000-0000-000000000001',5900,'UTR1')`,
    'segregation of duties');
  await runAs('authenticated', U.admin,
    `insert into public.payments(payment_no, payment_type, invoice_id, amount, reference)
     values ('PMT-1','customer_receipt','b0000000-0000-0000-0000-000000000001',5900,'UTR1')`)
    .then(() => check('segregation: a different user can record the payment', true))
    .catch((e) => check('segregation: a different user can record the payment', false, e.message));
  const paid = (await db.query(`select status from public.invoices where id='b0000000-0000-0000-0000-000000000001'`)).rows[0].status;
  check('trigger: invoice status derived to paid', paid === 'paid', paid);
  await expectError('lock: a paid invoice cannot be edited', 'authenticated', U.accounts,
    `update public.invoices set grand_total = 1 where id='b0000000-0000-0000-0000-000000000001'`,
    'cannot be edited');

} catch (e) {
  log('HARNESS ERROR: ' + e.message);
  fail++;
}

log('');
log(`RESULT: ${pass} passed, ${fail} failed`);
console.log(lines.join('\n'));
process.exit(fail ? 1 : 0);
