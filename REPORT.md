# REPORT — Ramprasad Defence: database schema implementation

**Scope of this task:** implement the Supabase database architecture (schema, keys, statuses,
role-based security, RLS, audit). Do not proceed to the UI until the schema is validated.

**Date:** 2026-10-07.

---

## Status per part

**Database schema (41 tables) — DONE**
- evidence: 13 migration files written under `supabase/migrations/` and applied in order against
  PostgreSQL (PGlite). Output of `npm test` in `supabase/tests`:
  ```
  applied 0001_foundation.sql
  applied 0002_identity.sql
  applied 0003_security_helpers.sql
  applied 0004_masters.sql
  applied 0005_documents.sql
  applied 0006_tenders.sql
  applied 0007_quotations.sql
  applied 0008_orders_procurement.sql
  applied 0009_receipts_inspection.sql
  applied 0010_dispatch_finance.sql
  applied 0011_ops.sql
  applied 0012_rls.sql
  applied 0013_triggers.sql
  seeded 0001_roles.sql
  ... (32 checks) ...
  RESULT: 32 passed, 0 failed
  ```

**Primary/foreign keys, no duplicate data — DONE**
- evidence: every table has a `uuid` PK; FKs on every relationship; each line `line_total` is a
  `GENERATED` column (`generated: line_total = 2*100*0.9*1.18 = 212.40` PASS); header totals
  recalculated from lines (`quotation subtotal = 230.00`, `grand_total = 271.40` PASS).

**created_at / updated_at / status / audit fields — DONE**
- evidence: `trigger: updated_at changes on update` PASS; status `CHECK` constraints rejected
  bad data (`tender bid_due before received is rejected`, `tender_requirement quantity 0 is
  rejected` PASS); `created_by`/`updated_by` default to the signed-in user; `audit_logs`
  written on every change (`audit: insert wrote an audit_logs row` PASS).

**Role-based security + RLS — DONE**
- evidence: `RLS: authenticated-but-no-user sees 0 tenders`, `viewer cannot insert customer`,
  `sales can insert tender`, `accounts cannot insert purchase order`, `viewer can read tenders`,
  `logistics sees only non-controlled documents (1)`, `technical sees controlled documents too
  (2)` — all PASS.

**Audit append-only — DONE**
- evidence: `audit append-only: admin delete removed 0 audit rows` PASS; `no insert policy lets
  a normal user forge audit rows` PASS.

**Business-integrity gates — DONE**
- evidence: `PDI gate: dispatch blocked before any passed PDI` PASS; `blocked on failed PDI`
  PASS; `allowed after passed PDI` PASS; `segregation: invoice creator cannot record its
  payment` PASS (and a different user can); `lock: a paid invoice cannot be edited` PASS;
  `invoice status derived to paid` PASS.

**Secrets not in source — DONE**
- evidence: `.env.example` lists variable NAMES only; `.gitignore` excludes `.env`, `.env.*`,
  `*.pem`, `*.key`, `node_modules/`; no key value appears in any migration.

**Every table documented — DONE**
- evidence: `docs/DATABASE.md` documents all 41 tables (purpose, columns, statuses, links);
  SQL also carries `COMMENT ON TABLE/COLUMN` for each table.

**Apply to a live Supabase project — BLOCKED**
```
BLOCKED: cannot create cloud resources without the owner's Supabase project + credentials
  Tried:      docker info (to run a full local Supabase)
  Got:        "failed to connect to the docker API ... check if the daemon is running"
  Wall:       No live Supabase project URL / keys in this environment, and the Docker
              engine is not running for the local Supabase stack.
  To unblock: Create a Supabase project, give me the project ref + service key (in .env.local,
              never in chat), start Docker Desktop, then run: supabase link && supabase db push
```

**UI — NOT STARTED** (per the instruction to validate the database first).

---

## What broke and how I fixed it

1. **PGlite function returned the wrong type** — `first guess: the `->>` operator returns text,
   not uuid. Changed the helper to cast `(... ->> 'sub')::uuid`. Smoke test then passed.**
2. **RLS insert was refused in the smoke test** — expected: no insert policy existed, so
   default-deny worked. Added a scoped insert policy and re-ran; the foreign-row insert was
   still denied and the owner saw only their own row.
3. **One acceptance test failed (`admin cannot delete audit_logs`)** — the schema was correct;
   the *test* was wrong. RLS on `DELETE` filters rows silently (0 rows) instead of raising.
   Rewrote the assertion to prove 0 audit rows were removed. 32/32 then passed. This is the
   `AGENTS.md` rule applied: a test must fail when the feature is wrong.

---

## Claims ledger

| Claim | Proof | Status |
|---|---|---|
| 41 tables, 13 migrations, 1 seed | `npm test` applied all; `information_schema` count >= 41 | Proven (PGlite) |
| RLS default-deny works | `RLS: authenticated-but-no-user sees 0 tenders` | Proven (PGlite) |
| Role writes are enforced in the DB | `accounts cannot insert purchase order` | Proven (PGlite) |
| Controlled documents are restricted | `logistics sees only non-controlled (1)` / `technical sees 2` | Proven (PGlite) |
| Append-only audit | `admin delete removed 0 audit rows`; forge insert denied | Proven (PGlite) |
| PDI gate blocks dispatch | blocked before/failed PDI; allowed after pass | Proven (PGlite) |
| Segregation of duties | invoice creator blocked from recording payment | Proven (PGlite) |
| Paid invoice locked | `a paid invoice cannot be edited` | Proven (PGlite) |
| Generated line totals correct | `212.40`; header `271.40` | Proven (PGlite) |
| Schema applied to live Supabase | — | **UNVERIFIED — BLOCKED** (no credentials) |
| MFA / session / private bucket policies | — | **UNVERIFIED** (dashboard config, next phase) |

No claim above was made without running it. The live-Supabase items are explicitly unverified.

---

## What I would tell the next person

1. **The migrations are the source of truth.** Apply them with `supabase db push` in filename
   order; never edit tables by hand in the dashboard, or the migrations and reality diverge.
2. **Re-run the tests after any schema change:** `cd supabase/tests; npm install; npm test`.
   They run real PostgreSQL in-process; a red test means the change broke the model, not the test.
3. **Do not weaken RLS to make a screen work.** If the UI needs data, add a policy deliberately
   and add a test that proves the boundary still holds.
4. **Resolve data residency (PRD §10 Q1) before deploying to a cloud region**, and get legal
   sign-off before storing any `itar_ear` document (the table supports the classification; the
   legal basis for storing such data is a separate decision).
5. **Status values are `CHECK` constraints.** Renaming a status is a migration, not a data edit.
   If statuses will change often, move to a lookup table (documented in DATABASE.md §14).
6. **Added beyond the requested list:** `user_roles`, `invoice_items`, `purchase_request_items`,
   `material_receipt_items`, `dispatch_items` — required for role grants and for line-level
   reconciliation. Say so if you want them removed.

---

# Tender Management module — added 2026-10-07

**Scope:** build the Tender Management UI module (list, search, filters, create/edit, detail,
documents, assign, status pipeline, closing date, priority, requirements, notes, tasks,
activity history, deadline indicators). Do not add features beyond the request.

## Decisions recorded

- **UI platform:** the **Next.js escape hatch** was used (see `TECH-STACK.md` §2.4), because no
  low-code platform is connected and no live Supabase credentials exist here. The database and
  RLS are unchanged, so a low-code UI can still be added later.
- **Schema change (migration `0014_tender_workflow.sql`):** the tender status set was replaced
  with the agreed **13-stage pipeline**, and a `tender_notes` table was added (a tender needs
  many timestamped notes), plus a tender-activity read policy on `audit_logs` and a read-only
  `user_directory` view. See `docs/DATABASE.md` and `docs/SECURITY.md`.

## Status per part

**Database support for the module — DONE**
- evidence: `npm test` in `supabase/tests` → `RESULT: 37 passed, 0 failed` (includes
  `workflow: unknown tender status is rejected`, `valid pipeline status accepted`,
  `sales can add a tender note`, `viewer cannot add a tender note`).

**Tender list, search, filters — DONE**
- evidence: `src/app/tenders/page.tsx` + `src/components/TenderFilters.tsx`; build lists route
  `/tenders`. Search is a plain GET form (works without JavaScript).

**Create / edit tender — DONE**
- evidence: `src/app/tenders/new/page.tsx`, `src/app/tenders/[id]/edit/page.tsx`,
  `src/components/TenderForm.tsx`; required fields enforced by `src/lib/validation.ts`.

**Tender detail page — DONE**
- evidence: `src/app/tenders/[id]/page.tsx` (pipeline, closing date, priority, assign,
  requirements, notes, tasks, documents, activity).

**Documents upload — DONE**
- evidence: `uploadDocument` in `src/app/tenders/actions.ts` (private bucket + signed download
  links).

**Assign employee — DONE** — `assignTender` + `user_directory` view.
**Status pipeline (13 stages) — DONE** — `src/lib/tenderStatus.ts` + `StatusPipeline.tsx`.
**Closing date, priority — DONE** — tender form and detail.
**Requirement section — DONE** — `addRequirement` + requirements table.
**Notes — DONE** — `addNote` + `tender_notes`.
**Tasks — DONE** — `addTask` / `completeTask` on the `tasks` table.
**Activity history — DONE** — `getActivity` reads `audit_logs` for the tender.
**Deadline indicators (green/yellow/red) — DONE** — `src/lib/deadline.ts` + `DeadlineBadge.tsx`.

**Build and tests — DONE**
- evidence: `npm run build` → `✓ Compiled successfully`, `✓ Generating static pages (7/7)`;
  routes `/`, `/login`, `/tenders`, `/tenders/[id]`, `/tenders/[id]/edit`, `/tenders/new` +
  Middleware compiled. `npm test` → `Test Files 1 passed (1)`, `Tests 10 passed (10)`.

**Run against a live Supabase project — BLOCKED**
```
BLOCKED: cannot run the app against a live database
  Tried:      npm run build (ok) / npm test (ok)
  Got:        no Supabase project URL/keys in this environment; Docker engine not running
  Wall:       The UI can be built and tested offline, but signing in and reading real rows
              needs a Supabase project.
  To unblock: complete app/README.md setup (project, migrations, bucket, first user, .env.local).
```

## What broke and how I fixed it

1. **`npm install` failed: registry tarballs missing for the latest `@supabase/*` packages**
   (`@supabase/auth-js@2.117.3`, `@supabase/realtime-js@2.117.3` → 404/ETARGET). Pinned exact,
   known-complete versions (`@supabase/supabase-js@2.45.4`, `@supabase/ssr@0.5.2`) and install
   succeeded.
2. **`next@14.2.15` flagged with a security advisory.** Bumped to the patched `14.2.35`;
   install and build still pass.
3. **CSS build warnings** (`align-items: end`). Changed to `flex-end`; warnings gone.

## Claims ledger (module)

| Claim | Proof | Status |
|---|---|---|
| 13-stage pipeline in DB | `npm test` → 37/37, status tests pass | Proven (PGlite) |
| Tender notes table + RLS | `sales can add a tender note` / `viewer cannot` | Proven (PGlite) |
| App compiles and type-checks | `npm run build` → `✓ Compiled successfully` | Proven |
| Deadline colours logic | `npm test` → 10/10 (green/yellow/red/overdue/high-risk) | Proven |
| Search / filters / list render | route `/tenders` in build output | Proven (compiles) |
| Live sign-in and real rows | — | **UNVERIFIED — BLOCKED** (no credentials) |
| Document upload to Storage | code path present; private bucket required | **UNVERIFIED** (needs live project) |

---

# Quotation Management module — added 2026-10-07

**Scope:** build the Quotation Management UI module (create, multiple products, automatic
calculations, margin, technical compliance, approval workflow, revision history, PDF generation,
download, status, follow-up task; never overwrite an approved quotation; complete audit history).

## Schema change (migration `0015_quotation_module.sql`)

- **Line level:** `purchase_unit_cost`, `logistics_unit_cost`, `other_unit_cost`,
  `technical_compliance`, plus generated `line_base`, `line_cost`, `line_margin`,
  `line_margin_pct`.
- **Header level:** `payment_terms`, `delivery_terms`, `warranty`, `revision_of`, `approved_by`,
  `approved_at`, `total_purchase_cost`, `total_logistics_cost`, `total_other_cost`,
  `total_margin`.
- **Triggers:** `app.recalc_quotation_totals()` (totals/cost/margin from lines);
  `app.protect_approved_quotation()` and `app.protect_approved_quotation_items()` (an
  approved/submitted/won/lost quotation and its lines are frozen — a revision is required).
- **One approved approval step per quotation** (unique partial index) — no double approval.
- Quotation activity readable by staff via a new `audit_logs` policy.

## Status per part

**Create quotation, link Customer / Tender / Requirement / OEM / Products — DONE**
- evidence: `src/app/quotations/new/page.tsx`, `src/app/quotations/[id]/page.tsx`; the add-line
  form selects product, OEM (`source_oem_id`) and tender requirement.

**Add multiple products — DONE** — `addQuotationItem` / `removeQuotationItem`.
**Automatic calculations — DONE** — generated columns + `recalc_quotation_totals`; proven below.
**Margin calculation — DONE** — `line_margin`, `line_margin_pct`, `total_margin`; proven.
**Technical compliance status — DONE** — `technical_compliance` per line + rollup badge.
**Approval workflow — DONE** — `submitForApproval`, `decideQuotation` (management/admin only).
**Revision history / never overwrite approved — DONE** — `createRevision` + freeze triggers.
**PDF generation / download — DONE** — `src/lib/quotationPdf.ts` + route `/[id]/pdf`.
**Quotation status — DONE** — 9 statuses, selector + labels.
**Follow-up task — DONE** — `addFollowUpTask` (tasks linked to the quotation).
**Complete audit history — DONE** — every change writes `audit_logs`; shown on the page.

**Evidence (schema + triggers) — DONE**
- evidence: `npm test` in `supabase/tests` → `RESULT: 45 passed, 0 failed`, including:
  `quotation: line margin = 80.00`, `line margin % = 44.44`, `header costs + margin`,
  `invalid technical compliance rejected`, `approved header cannot be edited`,
  `approved lines cannot be changed`, `revision is a new v2 row linked to v1`,
  `previous version may be marked revised`.

**Evidence (app) — DONE**
- evidence: `npm run build` → `✓ Compiled successfully`, `✓ Generating static pages (9/9)`,
  routes include `/quotations`, `/quotations/[id]`, `/quotations/[id]/edit`,
  `/quotations/[id]/pdf`, `/quotations/new`.
- evidence: `npm test` in `app` → `Test Files 2 passed (2)`, `Tests 15 passed (15)`, including
  `generates a real PDF document` (asserts the output begins with `%PDF` and is non-trivial).

**Run against a live Supabase project — BLOCKED** (same reason as the tender module; see above).

## Claims ledger (quotation module)

| Claim | Proof | Status |
|---|---|---|
| Automatic cost/margin calculation | schema tests: line margin 80.00, 44.44%, header margin 130 | Proven (PGlite) |
| Approved quotation is immutable | `approved header cannot be edited` / `approved lines cannot be changed` | Proven (PGlite) |
| Revision is a new row, original untouched | `revision is a new v2 row linked to v1` | Proven (PGlite) |
| Technical compliance value enforced | `invalid technical compliance rejected` | Proven (PGlite) |
| PDF generation produces a real PDF | app test `generates a real PDF document` (%PDF) | Proven |
| Approval restricted to management/admin | policy in `0012_rls.sql`; UI gate in `decideQuotation` | Proven (policy) / code |
| Live approval + PDF download from a real project | — | **UNVERIFIED — BLOCKED** (no credentials) |

---

# Procurement module — added 2026-10-07

**Scope:** implement the procurement workflow (customer order → material requirement →
purchase request → OEM RFQ → OEM quotation → OEM selection → purchase approval → purchase order
→ expected delivery → material receipt → PDI → ready for dispatch), with tracking of OEM,
product, quantity, purchase price, expected/actual delivery, payment terms, warranty,
compliance documents and status, plus **automatic risk indicators** when OEM delivery may delay
the customer delivery.

## Schema change (migration `0016_procurement_module.sql`)

- New tables: `material_requirements`, `material_requirement_items`, `oem_rfqs`,
  `oem_rfq_items`, `oem_quotations`, `oem_quotation_items`, `purchase_approvals`,
  `procurement_documents` (8 new tables → 50 total).
- New columns: `purchase_requests.material_requirement_id`; `purchase_orders.oem_quotation_id`,
  `material_requirement_id`, `payment_terms`, `warranty`, `actual_delivery_date`.
- Triggers: OEM quotation totals (`app.recalc_parent_totals`); PO actual-delivery from receipts
  (`app.recalc_po_actual_delivery`); one-approved-approval-per-PO unique index; updated_at +
  audit on every new table; a procurement-activity `audit_logs` read policy.

## Status per part

**Workflow stages — DONE** — pages/actions cover requirement → purchase request → RFQ → OEM
quotation → selection (creates PO) → approval → expected delivery → receipt → PDI → ready for
dispatch. Evidence: `npm run build` routes `/procurement`, `/procurement/requirements/new`,
`/procurement/requirements/[id]`, `/procurement/rfqs/[id]`, `/procurement/quotations/[id]`,
`/procurement/orders/[id]`.

**Track OEM / product / quantity / purchase price / expected delivery / actual delivery /
payment terms / warranty / compliance documents / status — DONE** — captured across
`oem_quotations`, `purchase_orders`, `purchase_order_items`, `material_receipts`,
`procurement_documents`; `actual_delivery_date` is maintained from receipts by trigger.

**Automatic delivery-risk indicators — DONE** — `src/lib/procurement.ts#deliveryRisk`, shown on
the dashboard and PO page.

**Evidence (schema + triggers) — DONE**
- evidence: `npm test` in `supabase/tests` → `RESULT: 50 passed, 0 failed`, including
  `material requirement qty 0 rejected`, `OEM quotation totals (200 / 36 / 236)`,
  `cannot approve the same PO twice`, `duplicate compliance document link rejected`,
  `actual delivery date set from receipt`.

**Evidence (app) — DONE**
- evidence: `npm test` in `app` → `Test Files 3 passed (3)`, `Tests 24 passed (24)`, including
  the 7 delivery-risk cases (green/yellow/red: overdue, will-miss, tight, no-date, delivered).
- evidence: `npm run build` → `✓ Compiled successfully`, `✓ Generating static pages (11/11)`,
  all `/procurement/*` routes present.

**Run against a live Supabase project — BLOCKED** (same reason as prior modules; see above).

## Claims ledger (procurement module)

| Claim | Proof | Status |
|---|---|---|
| Chain of tables exists and enforces rules | schema tests 50/50 | Proven (PGlite) |
| OEM quotation totals calculate | `OEM quotation totals (200 / 36 / 236)` | Proven (PGlite) |
| One approval per PO | `cannot approve the same PO twice` | Proven (PGlite) |
| Actual delivery tracked from receipts | `actual delivery date set from receipt` | Proven (PGlite) |
| Risk indicator rules | 7 app tests (overdue / will-miss / tight / no-date / delivered) | Proven |
| Live procurement run end to end | — | **UNVERIFIED — BLOCKED** (no credentials) |

---

# Management dashboard — added 2026-10-07

**Scope:** a read-only management dashboard with the 16 requested numbers, each drillable to the
underlying records, without exposing data to users who lack permission. **No schema change.**

## Status per part

All 16 metrics are computed in `src/lib/dashboard.ts` and shown as tiles on `/dashboard`, each
linking to `/dashboard/<metric>` which lists the underlying records with links to the record:

| # | Metric | Definition | Drill links to |
|---|---|---|---|
| 1 | Active tenders | tender not won/lost/cancelled | tender |
| 2 | Tenders closing soon | bid due within 7 days | tender |
| 3 | Submitted tenders | status submitted | tender |
| 4 | Won tenders | status won | tender |
| 5 | Lost tenders | status lost | tender |
| 6 | Active customer orders | order not closed/cancelled | order |
| 7 | Orders at delivery risk | PO risk red/yellow | PO |
| 8 | Delayed orders | expected date passed, not received | PO |
| 9 | Pending OEM deliveries | PO approved/sent/partially received | PO |
| 10 | Pending PDI | receipt inspection pending/in progress | receipt |
| 11 | Pending dispatch | order line not fully dispatched | order line |
| 12 | Outstanding payments | issued invoice with a balance | invoice |
| 13 | Overdue payments | outstanding invoice past due date | invoice |
| 14 | Monthly sales | order value per month (last 12) | month rows |
| 15 | Gross margin | margin on approved/submitted/won quotations | quotation |
| 16 | OEM performance | on-time / late / pending / at-risk per OEM | OEM |

**Drill-down — DONE** — every tile is a link; `/dashboard/[metric]` renders the filtered records.
**Permission safety — DONE** — server-side gate to admin/management; all queries run under the
user's session so RLS still applies (see `docs/SECURITY.md`).

## Evidence

- evidence: `npm test` in `app` → `Test Files 4 passed (4)`, `Tests 27 passed (27)`, including
  `management dashboard access is limited to management and administrators`,
  `monthly sales aggregation`, and `OEM performance counts on-time, late, pending and at-risk`.
- evidence: `npm run build` → `✓ Compiled successfully`, `✓ Generating static pages (12/12)`,
  routes `/dashboard` and `/dashboard/[metric]` present.

## Claims ledger (dashboard)

| Claim | Proof | Status |
|---|---|---|
| Dashboard restricted to admin/management | app test `management dashboard access ...` | Proven |
| Monthly sales aggregation correct | app test `monthly sales aggregation` | Proven |
| OEM performance correct | app test `OEM performance` | Proven |
| Each metric drills to records | `/dashboard/[metric]` route built; tiles link to it | Proven (build) |
| Figures respect RLS | queries run under the user's Supabase session | Proven (design) / RLS tests |
| Live dashboard with real data | — | **UNVERIFIED — BLOCKED** (no credentials) |




