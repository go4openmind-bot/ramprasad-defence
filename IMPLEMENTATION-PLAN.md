# IMPLEMENTATION-PLAN — Ramprasad Defence: Defence Contract & Supply Management System

**Status: DRAFT — PLAN ONLY. Do not start Phase 1 until the owner approves this plan and
answers `PRD.md` §10.** This document is the step-by-step build order, project structure and
acceptance checks. It is written so a non-programmer can follow it by pasting one step at a
time into Kilo Code.

**Read in this order before building:** `PRD.md`, then `TECH-STACK.md`, then `DATABASE-ERD.md`,
then this file. If chat and these documents disagree, the documents win.

---

## 0. How to work (rules that apply to every step)

1. **One slice at a time.** Never say "build the whole system". Give the numbered step only.
2. **Always demand evidence.** Every step ends with: run the check, paste the REAL output.
   Never claim something works unless it was run just now; otherwise write `UNVERIFIED`.
3. **Never paste secrets into chat.** Keys go in `.env.local` (git-ignored). If a key is ever
   exposed, rotate it immediately.
4. **Commit after every green check** with a clear message.
5. **Stop after three failures** on the same error and ask for a written diagnosis
   (`AGENTS.md` §4).
6. **Trust your eyes, not the summary.** The "Check" is what counts.
7. **Keep the log.** Update `WORKLOG.md` each slice (`what → command → what it printed`);
   write `REPORT.md` each phase.

**Universal wrapper — paste at the end of every step prompt:**

```
Rules for this task:
- Work in one small slice only. Do not build anything I did not ask for.
- Before changing anything, reply with a 5-bullet plan and the files you will touch. Then implement.
- Read whole error messages, not the last line. State one guess, make one change, re-run.
- After implementing, run the acceptance check yourself and paste the REAL command output.
- Never claim something works unless you ran it just now. If unverified, write UNVERIFIED.
- Put secrets only in .env.local, never in code, never in a commit. Confirm .gitignore covers it.
- Update WORKLOG.md with one line: what I did -> command -> what it printed.
- Do not weaken, delete or bypass any check to make it pass.
```

---

## 1. Project / folder structure

Everything lives under the project folder:

```
Ramprasad-Defence Project/
├── PRD.md                     # requirements, roles, workflow, MVP, security, risks
├── TECH-STACK.md              # architecture and component decisions
├── DATABASE-ERD.md            # ERD, tables, relationships, RLS approach
├── IMPLEMENTATION-PLAN.md     # this file
├── README.md                  # how to run/operate the system
├── WORKLOG.md                 # one line per completed slice
├── REPORT.md                  # phase reports + claims ledger
├── .gitignore                 # excludes .env.local, node_modules, exports
├── .env.example               # variable NAMES only, no values
│
├── supabase/
│   ├── migrations/            # versioned SQL: 0001_init.sql, 0002_masters.sql, ...
│   ├── seed/                  # status_definitions, roles, settings defaults
│   └── policies/              # RLS policies (also applied via migrations)
│
├── n8n/
│   ├── workflows/             # exported workflow JSON (reminders, alerts, digests)
│   └── README.md              # which workflow does what, and its schedule
│
├── lowcode/
│   ├── appsmith/              # exported low-code app (primary UI), or
│   └── budibase/              # alternative
│
├── scripts/
│   ├── import/                # Excel import with dry-run + dedupe report
│   └── backup/                # backup/restore helpers and instructions
│
├── app/                       # OPTIONAL Next.js "escape hatch" — built only if needed
│
└── docs/
    ├── SECURITY.md            # security settings checklist and runbook
    └── DECISIONS.md           # decision log (what changed and why)
```

**Notes**
- `app/` stays empty until a screen cannot be expressed in the low-code tool.
- `n8n/workflows/` holds **exports**, so workflows are reviewable and restorable.
- `supabase/migrations/` is the single source of truth for the schema — no dashboard-only
  edits to production tables.

---

## 2. Phase 0 — decisions and access (BLOCKING, no code)

Get these in writing. Nothing in Phase 1 can be built safely without them.

- **Owner decisions:** PRD §10 questions 1–10, especially **data residency (1)**, **export
  control (2)**, **role names (3)**, **approval threshold (4)**, **currency/tax (5)**,
  **low-code platform (7)**, **n8n hosting (8)**.
- **Access checklist:**
  - Supabase account (org owner) — for DB/Auth/Storage.
  - Region for the Supabase projects (dev + prod).
  - n8n host (self-hosted server or approved cloud) + its region.
  - Low-code platform account (Appsmith/Budibase) + host decision.
  - A business mailbox/SMTP for alerts.
  - Excel exports: customers, suppliers, products, open tenders, open orders, invoices/dues.
- **Controlled-data rule:** do not put any ITAR/EAR-controlled file into the system until
  question 2 is answered and legal review done (PRD R2).

**Check before moving on:** every decision above has an owner's name against it, and you can
log into Supabase, n8n and the chosen low-code platform yourself.

---

## 3. Phase-by-phase build

Order matters. Each phase ends with an owner-visible check.

### PHASE 1 — Foundation (identity, schema, security)
*Ships: users, roles, the full schema, RLS, and an audit trail — proven with tests.*

**1.1 Project skeleton**
- Goal: the folder structure above, `.gitignore`, `.env.example`, `README.md`, `WORKLOG.md`.
- Paste to Kilo:
  ```
  Create the folder structure in IMPLEMENTATION-PLAN.md section 1. Add a .gitignore that
  excludes .env.local, node_modules and any export/output folders; a .env.example listing
  every variable name we will need (Supabase URL, anon key, service key, n8n webhook base,
  SMTP) with NO values; a README.md; a WORKLOG.md. Add no product features.
  ```
- Check: `.env.local` does not appear in `git status`; `git status` is clean apart from the
  new files.
- Owner: none.

**1.2 Create Supabase projects (dev + prod) and connect**
- Goal: two projects, migrations applied from the repo, no secrets committed.
- Paste to Kilo:
  ```
  Connect this project to a Supabase dev project using the Supabase CLI. Store the URL and
  keys in .env.local only. Create supabase/migrations and verify I can run a migration from
  the repo to the dev project. Do not create business tables yet.
  ```
- Check: a trivial test migration appears in the Supabase dashboard; the service key is NOT in
  the repo.
- Owner: provide Supabase org access; confirm region (PRD §10 Q1).

**1.3 Identity and roles**
- Goal: `users`, `roles`, `user_roles`, `auth_user_id` mirror; MFA available.
- Paste to Kilo:
  ```
  Create the identity tables from DATABASE-ERD.md section 2.1. Add a trigger that creates a
  users row when a new auth user signs up, mirroring full_name/email and auth_user_id. Seed
  the 9 roles from PRD.md section 3. Enable MFA support. Show the migration and the trigger.
  ```
- Check: sign up a test user; a `users` row appears and can be given a role.

**1.4 Core schema**
- Goal: all tables in `DATABASE-ERD.md`, with constraints, indexes and default statuses.
- Paste to Kilo:
  ```
  Create migrations for every table in DATABASE-ERD.md sections 2.2–2.6, in dependency order,
  with the columns, checks, unique constraints and indexes listed there. Add status_definitions
  seeds for every entity's statuses. Money columns are numeric(14,2), quantities numeric(14,3).
  Show each migration and run it on the dev project.
  ```
- Check: in the dashboard all tables exist with the right columns; seeding produced the statuses.
- Owner: none.

**1.5 RLS and audit trail**
- Goal: default deny, role-based access, append-only audit, segregation of duties.
- Paste to Kilo:
  ```
  Enable RLS on every public table. Add policies implementing the permission matrix in PRD.md
  section 3.1, keyed to user_roles and auth.uid(). Make audit_log and status_events append-only.
  Add triggers that write audit_log on insert/update/delete and status_events on status change.
  Add the segregation-of-duties triggers (invoice creator != payment recorder; PO creator !=
  goods receiver). Show the policies and the triggers.
  ```
- Check (`AGENTS.md` §3 — the test must be able to fail): create a test user with the
  `accounts` role, request a `purchase_orders` row by id directly → the database refuses.
  Create a `viewer`, attempt an insert → refused. Confirm both, paste the output.
- Owner: none.

> **Gate:** do not proceed to Phase 2 until 1.5 passes. Everything after depends on RLS.

---

### PHASE 2 — Masters and data import
*Ships: real customers, suppliers and products in the system, imported from Excel.*

**2.1 Master screens / tables**
- Goal: create and manage customers, contacts, suppliers, products.
- Paste to Kilo:
  ```
  Build low-code screens for customers, customer contacts, suppliers, supplier contacts and
  products, backed by the tables from DATABASE-ERD.md. Enforce required fields with clear
  reasons and save nothing on invalid input. No duplicate codes.
  ```
- Check: create one customer, one supplier and one product; a duplicate code is rejected.

**2.2 Excel import with dry-run + dedupe**
- Goal: bring existing data in safely, with a report of what was skipped.
- Paste to Kilo:
  ```
  Build an import script in scripts/import that reads the owner's Excel exports for customers,
  suppliers and products. First run a DRY RUN that prints counts of new / duplicate / invalid
  rows and writes a report; only on confirmation import the valid rows. Dedupe by normalised
  code/GSTIN/name. Never silently drop a row — report every rejection with its reason.
  ```
- Check: run the dry run on the real file, read the report, then import; re-run and confirm
  zero duplicates are created (`AGENTS.md` §3 — the test must be able to fail).
- Owner: provide the Excel exports (Phase 0).

---

### PHASE 3 — Sales chain (S1–S5)
*Ships: tender → technical analysis → OEM RFQ → supplier quotes → customer quotation → customer PO.*

**3.1 Tender intake** — create/edit tenders, upload documents, required-field rejection,
bid-due-date highlighted. `Check:` a tender missing `bid_due_date` is rejected with a reason.

**3.2 Tender technical items** — line items with specs and feasibility; assign a technical owner.
`Check:` add 3 lines to a tender, mark one infeasible, and close that line with a reason.

**3.3 OEM RFQ and supplier quotes** — issue RFQs to suppliers, record and compare quotes side
by side. `Check:` two suppliers quote the same RFQ line; the comparison shows both, and a quote
with `validity_date < quote_date` is rejected.

**3.4 Versioned quotation with approval** — build quotes from selected supplier quote lines,
version them, route for management approval above the threshold, generate a PDF, record
submission. `Check:` submit Rev 0, create Rev 1; Rev 0 is unchanged. A quote above the
threshold cannot be submitted without approval (the test must fail without approval).

**3.5 Customer PO capture and matching** — record the customer PO, match lines to the
quotation, flag mismatches. `Check:` a PO line with no quotation match is flagged; a PO with no
lines is rejected.

---

### PHASE 4 — Procurement and fulfilment (S6–S9)
*Ships: OEM PO → goods receipt → inspection gate → dispatch.*

**4.1 Purchase orders to OEMs** — create POs linked to a customer order; approval if configured.
`Check:` a PO cannot reference a non-existent customer order.

**4.2 Goods receipt** — record supplier deliveries against a PO line; qty received vs ordered.
`Check:` receiving more than ordered is blocked unless the over-delivery flag is set.

**4.3 Inspection / PDI with a hard gate** — record inspection results; a `fail` blocks dispatch.
`Check:` try to dispatch a line whose inspection is `fail` → blocked. This is the pilot lesson
(`AGENTS.md` §3): the gate must be in the data path, not the screen.

**4.4 Dispatch and delivery confirmation** — record dispatch, POD, e-way bill.
`Check:` a dispatch cannot be created for a failed/uninspected line; after dispatch, the order
status moves and a `status_events` row exists.

---

### PHASE 5 — Finance (S10–S11)
*Ships: invoice → payment → ageing, with totals that reconcile.*

**5.1 Invoices** — raise invoices from a customer order/dispatch; totals computed by trigger
from invoice items; paid invoices locked. `Check:` an invoice whose `grand_total` is edited to
disagree with its line items fails to save (the test must fail on a wrong total).

**5.2 Customer payments and ageing** — record receipts, derive invoice status, show ageing
buckets. `Check:` record a part payment → status is `part_paid`; the rest → `paid`. An invoice
cannot be `paid` with an amount below its total.

**5.3 Supplier payments** — advances/partials/finals against POs, with references.
`Check:` a payment without a reference is rejected.

---

### PHASE 6 — Automation and dashboards
*Ships: the alerts and four dashboards that make the system better than Excel.*

**6.1 n8n connection** — self-hosted n8n with a restricted DB role / scoped key; one sample
workflow. `Check:` the sample workflow reads a test record and writes one notification; it
cannot read `payments`.

**6.2 Alerts** — bid due date approaching, quote awaiting approval, PO delivery overdue,
inspection failed, invoice overdue, weekly digest. `Check:` a test tender with a due date
tomorrow produces exactly one alert email.

**6.3 Dashboards** — (a) tenders due/expiring, (b) quotes awaiting approval, (c) orders in
fulfilment with blocked/overdue flag, (d) receivables ageing. `Check:` each number matches a
filtered list behind it that you can count by hand.

---

### PHASE 7 — Hardening and go-live
- Backups on (Supabase Pro), restore procedure documented and **rehearsed once**.
- MFA enforced for `admin`, `management`, `accounts`; session timeouts set.
- `docs/SECURITY.md` completed (settings checklist + runbook).
- Import remaining open orders/invoices/dues.
- Owner training in slices; Excel frozen for the core workflow; `REPORT.md` written.

---

## 4. MVP map (which phase delivers which MVP item)

| MVP item (PRD §7.1) | Delivered by |
|---|---|
| Auth + roles + RLS + audit | 1.3–1.5 |
| Masters | 2.1 |
| Excel import | 2.2 |
| S1–S5 sales chain | 3.1–3.5 |
| S6–S9 procurement/fulfilment | 4.1–4.4 |
| S10–S11 finance | 5.1–5.3 |
| Alerts + dashboards | 6.2–6.3 |
| Backups | 7 |

---

## 5. Timeline (order fixed, dates flexible)

| Phase | Content | Rough duration |
|---|---|---|
| 0 | Decisions + access | before code |
| 1 | Foundation | 1–2 weeks |
| 2 | Masters + import | 1 week |
| 3 | Sales chain | 2–3 weeks |
| 4 | Procurement/fulfilment | 2–3 weeks |
| 5 | Finance | 1–2 weeks |
| 6 | Automation + dashboards | 1–2 weeks |
| 7 | Hardening + go-live | 1 week |

Durations assume part-time work; the **order** does not change. If a phase slips, the next one
waits rather than being reordered.

---

## 6. First three actions

1. Hold the Phase 0 meeting; collect decisions and access (§2) and the Excel exports.
2. Answer `PRD.md` §10 questions 1–10 and mark this plan **approved**.
3. Then paste:
   ```
   Read PRD.md, TECH-STACK.md, DATABASE-ERD.md and IMPLEMENTATION-PLAN.md in that order.
   We are starting step 1.1 only.
   [then paste the universal wrapper from section 0]
   ```

---

## Decisions log

- 2026-10-07 — Implementation plan drafted as PLAN ONLY. Folder structure and Phases 0–7
  defined. No code, database or application created. Awaiting owner approval and the Phase 0
  decisions before step 1.1 begins.
