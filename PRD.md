# PRD — Ramprasad Defence: Defence Contract & Supply Management System

**Status: DRAFT — PLAN ONLY. Nothing is built.** This document is written to be approved or
corrected by the business owner before any database, table or screen is created.

**Purpose of this system:** replace the company's manual, Excel-based tracking of defence
tenders, OEM pricing, quotations, customer purchase orders, procurement, supplier delivery,
inspection, dispatch, invoicing, payments and repeat orders with one auditable system.

**How to read this document:** sections 1–9 are the requirement. Section 10 lists every open
question the owner must answer. Anything marked `ASSUMPTION` is a guess I made because the
owner was not interviewed; it must be confirmed before it becomes code. Anything marked
`UNVERIFIED` has not been checked against a real system yet.

> **Owner-facing rule from `AGENTS.md`:** never state an outcome that was not seen in real
> output. This document makes no claim that anything is live, working, or deployed. It is a plan.

---

## 1. Problem and context

Today the business runs a defence supply chain across spreadsheets and email. That creates
five specific, expensive failures:

1. **Tender deadlines are missed or nearly missed.** Bid due dates, EMD submission dates and
   extension (corrigendum) dates live in personal spreadsheets.
2. **OEM pricing is trapped in inboxes.** The same part is quoted by several OEMs; nobody can
   compare costs, and the "cost we used last time" is lost.
3. **Quotations cannot be reconstructed.** When a customer asks "what exactly did we quote on
   this line and at what price", someone digs through a folder.
4. **Delivery and inspection status is invisible.** Whether an item has arrived, passed PDI,
   or shipped to the customer is tracked by asking people.
5. **Money is untracked.** Which customer POs are invoiced, which invoices are unpaid, which
   supplier advances are paid — all manual.

The product is therefore **one auditable spine** (tender → quote → order → procure → receive →
inspect → dispatch → invoice → payment → repeat), not a collection of separate tools.

**Scale assumption (ASSUMPTION A1):** a single company, single location (or a small number of
offices that behave as one), roughly 10–50 internal users. This is not a 100,000-user product
and every architecture choice is made for that number.

---

## 2. Scope

### 2.1 In scope
- Tender / enquiry intake and tracking, with due-date and corrigendum alerts.
- Technical requirement capture and analysis per tender.
- OEM / supplier master, RFQ issuance, supplier price collection and comparison.
- Quotation preparation, approval and versioning to the defence customer.
- Customer purchase order (PO) capture and matching to the quotation.
- Procurement: purchase orders to OEMs, supplier advance/payment tracking.
- Supplier delivery and goods-receipt tracking.
- Inspection / PDI (Pre-Delivery Inspection) records, certificates and test results.
- Dispatch / shipment to the defence customer and delivery confirmation.
- Invoicing (customer receivables) and payment tracking.
- Repeat orders / contract renewals.
- Documents (tender docs, quotes, POs, inspection certs, invoices) stored centrally.
- Audit trail: who did what, when.
- Dashboards: "what needs attention today".

### 2.2 Out of scope (for now — revisit later)
- Automated bidding directly onto government portals (GeM / CPPP) via API. `ASSUMPTION A2`:
  these are recorded manually or by upload; integration is a later, separate project.
- Full accounting / GST filing / bank reconciliation. The system records invoice and payment
  status; it does not become an accounting package.
- E-signature of statutory documents.
- A customer/end-user self-service portal (possible Phase 2+, not MVP).
- Inventory/warehouse stock ledger with bin locations (MVP records receipts and dispatches; a
  full stock ledger is Phase 2).

### 2.3 Non-goals
- Replacing human judgement on pricing, eligibility or technical compliance.
- Making a bid decision automatically. The system informs; humans decide.

---

## 3. Actors and roles

| Role | Code | Who they are | Core job in the system |
|---|---|---|---|
| Administrator | `admin` | IT / system owner | Users, roles, settings, masters, nothing hidden |
| Managing Director / Management | `management` | Owner / directors | Read everything, approve quotes/POs, dashboards |
| Sales / Tender Executive | `sales` | BD team | Log tenders, follow up, prepare and submit quotes |
| Technical / Engineering | `technical` | Engineers | Analyse technical requirements, approve specs |
| Procurement Officer | `procurement` | Purchase team | RFQs to OEMs, POs, supplier follow-up |
| Stores / Receiving | `stores` | Store keeper | Record goods receipt against a PO |
| QA / Inspection | `qa` | Quality team | Record PDI / inspection results and certificates |
| Logistics / Dispatch | `logistics` | Dispatch team | Record dispatches and delivery confirmation |
| Accounts / Finance | `accounts` | Accounts team | Raise invoices, record payments, track dues |
| Viewer / Guest | `viewer` | Auditors, temp staff | Read-only, scoped |

**Segregation of duties (important):** the person who creates a purchase order should not be
the same person who confirms the goods were received, and the person who raises a customer
invoice should not be the same person who marks it paid. The system enforces this by
permission, not by convention (see section 7 and `TECH-STACK.md`).

### 3.1 Permission matrix (summary)

Legend: **F** = full (create/edit/delete within role), **E** = edit, **C** = create only,
**R** = read, **A** = approve, **—** = no access. Exact mapping is locked in the database RLS
policies (`DATABASE-ERD.md`).

| Area | admin | management | sales | technical | procurement | stores | qa | logistics | accounts | viewer |
|---|---|---|---|---|---|---|---|---|---|---|
| Users & roles | F | R | — | — | — | — | — | — | — | — |
| Masters (customers, OEMs, products) | F | R | E | R | E | R | R | R | R | R |
| Tenders / enquiries | F | R+A | F | E | R | — | R | — | R | R |
| Technical analysis | F | R | R | F | R | — | R | — | — | R |
| OEM RFQs & supplier quotes | F | R | R | R | F | — | R | — | R | R |
| Quotations to customer | F | A | F | R | R | — | — | — | R | R |
| Customer POs | F | R | F | — | R | — | — | — | R | R |
| Purchase orders to OEMs | F | A | — | — | F | R | — | — | R | R |
| Goods receipt | F | R | — | — | R | F | R | R | — | R |
| Inspection / PDI | F | R | — | R | — | R | F | — | — | R |
| Dispatch | F | R | — | — | — | R | R | F | — | R |
| Invoices | F | R | — | — | — | — | — | — | F | R |
| Payments | F | R | — | — | — | — | — | — | F | R |
| Repeat orders | F | R+A | F | — | R | — | — | — | R | R |
| Reports / dashboards | F | R | R | R | R | R | R | R | R | R |
| Audit log | F | R | — | — | — | — | — | — | R | R |

`ASSUMPTION A3`: these role names match the company's actual teams. The owner must rename
them to the real designations before build.

---

## 4. Functional requirements by lifecycle stage

Each stage lists what must be captured, the required fields (which the system must reject if
missing — `AGENTS.md` §3), and the records produced.

### S1. Tender / enquiry intake
- **Captured:** customer, tender/enquiry reference no., source, description, received date,
  bid due date, EMD/EMD-exemption, bid validity, currency, documents (upload), category.
- **Required:** customer, reference no., received date, bid due date.
- **Produces:** one `tenders` row plus `tender_documents`.

### S2. Technical requirement analysis
- Break the tender into requirement line items (quantity, unit, specification, technical
  parameters).
- Mark each line: feasible / needs OEM clarification / not feasible.
- Attach drawings, specifications, datasheets.
- **Produces:** `tender_items`, `tender_documents`; technical owner assigned.

### S3. OEM / supplier RFQ and price collection
- Select one or more OEM suppliers per tender line.
- Send RFQ (manually or via n8n email), record sent date and due date.
- Record each supplier's quote: price, currency, validity, MOQ, lead time, warranty,
  incoterms, taxes.
- Compare quotes side by side.
- **Produces:** `rfqs`, `rfq_items`, `supplier_quotes`, `supplier_quote_items`.

### S4. Costing and quotation to the customer
- Build the quotation from selected supplier quotes plus margin/packing/freight/installation/
  taxes.
- Version every quotation (`Rev 0, 1, 2`); never overwrite a submitted revision.
- Route for approval (management) above a configurable value; on approval, mark as submitted.
- Generate a PDF, store it, log submission date and reference.
- **Produces:** `quotations` (versioned), `quotation_items`, `documents`.

### S5. Award / customer purchase order
- Record the customer PO received: PO no., date, value, line items, delivery terms, payment
  terms, consignee.
- Match PO lines to the quotation lines; flag any mismatch.
- **Required:** customer, PO no., PO date, at least one line.
- **Produces:** `customer_orders`, `customer_order_items`.

### S6. Procurement
- Raise purchase orders to the selected OEM(s), linked to the customer order.
- Track OEM PO status, expected delivery, supplier advances/payments.
- **Produces:** `purchase_orders`, `purchase_order_items`, `supplier_payments`.

### S7. Supplier delivery and goods receipt
- Record supplier dispatch (docket/waybill), expected arrival, actual receipt.
- Record quantity received vs ordered; short/excess/damaged.
- **Produces:** `supplier_deliveries`, `delivery_items`.

### S8. Inspection / PDI
- Record inspection type (incoming, in-process, final, PDI, DGQA/third-party), date,
  inspector, result (pass / fail / conditional), certificate number, test reports.
- Fail triggers a non-conformance record and blocks dispatch until cleared.
- **Produces:** `inspections`, `inspection_items`, `documents`.

### S9. Dispatch to defence customer
- Record dispatch: dispatch no., date, carrier, consignee, invoice reference, e-way bill,
  items and quantities, packing list.
- Track transit and delivery confirmation (POD).
- **Produces:** `dispatches`, `dispatch_items`.

### S10. Invoicing
- Raise customer invoice against a customer order / dispatch; line items, taxes, totals.
- Version/void rules; never edit a paid invoice.
- **Produces:** `invoices`, `invoice_items`.

### S11. Payment tracking
- Record customer receipts and outstanding dues against invoices.
- Record supplier payments against PO/GRN.
- Ageing view (0–30, 31–60, 61–90, 90+ days).
- **Produces:** `payments` (receivables), `supplier_payments` (payables).

### S12. Repeat orders
- Flag items/contracts eligible for repeat or AMC renewal; create a new order from a prior one.
- **Produces:** `repeat_orders` linking to a prior customer order.

---

## 5. Complete workflow (end to end)

```
  [S1] Tender / Enquiry received
        │  (log customer, ref, bid due date, docs)
        ▼
  [S2] Technical requirement analysis ──► infeasible? ──► close with reason
        │  (line items, specs, feasibility)
        ▼
  [S3] RFQ to OEMs ──► supplier quotes received ──► comparison
        │
        ▼
  [S4] Quotation prepared ──► Management approval ──► Submitted to customer
        │                                              │
        │                        (bid due date / corrigendum alerts via n8n)
        ▼
  [S5] Customer PO received ──► matched to quotation ──► order confirmed
        │
        ├───────────────────────────────┐
        ▼                               ▼
  [S6] Purchase Orders to OEMs     (parallel) supplier advances tracked
        │
        ▼
  [S7] Supplier delivery ──► Goods receipt (qty vs ordered)
        │
        ▼
  [S8] Inspection / PDI ──► fail → non-conformance → rework/replacement → re-inspect
        │ pass
        ▼
  [S9] Dispatch to defence customer ──► POD / delivery confirmation
        │
        ▼
  [S10] Invoice raised
        │
        ▼
  [S11] Payment received ──► dues cleared / ageing
        │
        ▼
  [S12] Repeat order / AMC renewal → new S5 (or S1)
```

**Stage gates that block progress (enforced by the system):**
- Cannot submit a quotation without at least one priced line and an approval above the
  configured threshold.
- Cannot receive goods against a PO that does not exist.
- Cannot dispatch an item whose inspection is not `pass`.
- Cannot mark an invoice `paid` unless the receipt has been recorded with a date and amount.
- Cannot mark a supplier payment `paid` without a reference.

**Every stage transition writes an append-only event** (`status_events`) with actor, time,
from-status and to-status — this is the audit trail, not an optional feature.

---

## 6. Security requirements

Because this system handles defence procurement information, security is a first-class
requirement, not a phase.

1. **Authentication:** every user has an individual login. No shared passwords. Email +
   password with strong policy, MFA available (and required for `admin`, `management`,
   `accounts`). MFA and session timeouts are config in Supabase Auth.
2. **Authorization:** role-based access enforced **in the database** with Row Level Security,
   not in the screens. A request for a row the user may not see must be refused by the
   database even if made directly.
3. **Segregation of duties:** create/approve/receive/pay are separate permissions (section 3).
4. **Audit trail:** append-only `audit_log` + `status_events` for every create, update, delete,
   approval, submission, receipt, dispatch and payment. Deletes are soft-deletes.
5. **Documents:** stored in Supabase Storage in private buckets. Access only via short-lived
   signed URLs generated for an authenticated, authorized user. No public buckets.
6. **Data sensitivity / export control (see risks):** documents may contain controlled technical
   data. MVP stores a **classification** field on documents (`unclassified / internal /
   controlled / itar_ear`) and restricts `controlled`/`itar_ear` to named roles. Storing
   ITAR/EAR-controlled data may require controls beyond this stack — flagged in section 9.
7. **Secrets:** all keys (Supabase service key, n8n credentials, SMTP) live only in server-side
   environment variables. Never in browser code, never in a repo, never in a URL.
8. **Encryption:** TLS in transit (all vendors), encryption at rest (Supabase/Vercel default).
9. **Backups:** daily automatic backups once on Supabase Pro; documented restore procedure;
   PITR only if the owner judges daily insufficient (cost noted in `TECH-STACK.md`).
10. **Least privilege for automation:** n8n uses its own restricted database role / API key,
    not the master key, and only the workflows it needs.
11. **Logging and monitoring:** auth logs, database logs, and n8n execution logs retained;
    failed logins and permission denials reviewable.
12. **Data residency:** `ASSUMPTION A4` — defence data may legally need to stay in India.
    Supabase region selection is a **blocking decision** before build (see risks). If India
    residency is mandatory and Supabase cannot meet it, the whole stack must be reconsidered.

---

## 7. MVP definition (what "version 1" ships)

**MVP goal:** one company can run its real tender-to-payment cycle in the system, with roles,
audit and alerts, and stop using the core spreadsheets.

### 7.1 In the MVP
- Auth + 9 roles + RLS + audit trail (foundation, must come first).
- Masters: customers, OEM suppliers, products/item master.
- S1–S5: tender intake → technical items → OEM RFQ → supplier quote → versioned quotation →
  customer PO.
- S6–S9: OEM PO → goods receipt → inspection/PDI (pass/fail gate) → dispatch.
- S10–S11: invoice → payment tracking with ageing.
- Document storage for tender docs, quotes, POs, inspection certs, invoices.
- Four dashboards: (a) tenders due / expiring, (b) quotes awaiting approval, (c) orders in
  fulfilment with a blocked/overdue flag, (d) receivables ageing.
- Email alerts via n8n for: bid due date approaching, quote approval pending, PO not
  delivered in time, inspection failed, invoice overdue.
- Excel import for existing customers, suppliers, products and open tenders/orders.
- Daily backups.

### 7.2 Deliberately NOT in the MVP
- GeM/CPPP portal integration.
- Full stock/inventory ledger.
- Customer self-service portal.
- Full accounting/GST filing.
- Offline/mobile app.
- Analytics beyond the four dashboards.

### 7.3 MVP acceptance checks (what the owner personally verifies)
1. A user who is not logged in can read nothing (attempt a direct data request → refused).
2. A `procurement` user cannot see `accounts` data, and an `accounts` user cannot create a PO.
3. A tender with a missing bid due date is rejected with a reason and saves nothing.
4. An item cannot be dispatched while its inspection is `fail`.
5. An invoice cannot be marked paid without a receipt date and amount.
6. Every status change appears in the audit trail with the acting user and timestamp.
7. An imported Excel file produces no duplicate customers/suppliers (dedupe by normalised
   identifier) and reports what it skipped before writing.

---

## 8. Assumptions

| # | Assumption | Default chosen | Change this if |
|---|---|---|---|
| A1 | Scale | Single company, single location, 10–50 users | Multi-branch/group → every table and RLS policy changes |
| A2 | Portal integration | None; manual/upload from GeM/CPPP | API access exists → separate integration project |
| A3 | Role names | The 9 roles in section 3 | Real designations differ → rename before build |
| A4 | Data residency | Must confirm; Supabase region chosen for India proximity | India-only residency required → stack must be re-evaluated |
| A5 | Existing data | Excel exports are obtainable | No data → skip import; system works going forward |
| A6 | Currency/tax | INR primary, USD for imported OEMs; GST as configured | Other currencies/tax scheme → extend money fields (already multi-currency ready) |
| A7 | Approvals | Management approves quotations above a configurable value | No approval needed → threshold set to 0 disables it |
| A8 | Internet | Reliable office internet; desktop/laptop use | Field/offline use needed → offline/mobile is a later phase |
| A9 | Email | A business mailbox/SMTP is available for alerts | No email → alerts shown in-app only |
| A10 | Hosting | n8n and the admin UI run somewhere the owner controls | Data-residency rules forbid cloud n8n → self-host in the permitted region |

---

## 9. Risks (including defence-specific)

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| R1 | **Data residency / defence classification.** Defence data may be required to stay in India; Supabase regions are outside India (as of writing). `UNVERIFIED` against current Supabase region list. | Medium | Critical | Resolve A4 **before** creating the database. If India residency is mandatory, evaluate self-hosted Postgres or an India-region provider. Do not put controlled data in a non-approved region. |
| R2 | **Export control (ITAR/EAR).** Controlled technical data stored in a cloud tool without controls breaches export rules. | Medium | Critical | Classification field + role restriction in MVP; legal review before storing any `itar_ear` data; if strict, keep such files out of the system entirely. |
| R3 | **n8n data path.** Cloud n8n sees the data it moves (e.g. tender details in emails). | Medium | High | Self-host n8n in the approved region, or send only minimal notification text and pointers, never attachments with controlled data. |
| R4 | Excel data quality is poor (duplicates, missing fields). | High | Medium | Import with a dry-run preview and dedupe report; reject incomplete rows and report them; never silently drop. |
| R5 | Adoption — staff keep using Excel alongside. | High | High | Owner mandates one source of truth; MVP must be easier than the spreadsheet for the daily task; train in slices. |
| R6 | Free-tier limits / service pausing. | Medium | Medium | Supabase Free pauses after ~1 week idle and has no automatic backups. Move to Pro before real money data. |
| R7 | Supplier responsiveness (OEM quotes late). | High | Medium | RFQ due-date reminders via n8n; comparison view shows missing quotes. |
| R8 | Single-person dependency (only one person understands the Excel). | Medium | High | The import and the audit trail externalise that knowledge into the system. |
| R9 | Incorrect money figures (rounding, wrong tax). | Medium | High | Exact decimal (`numeric`) money, server-side totals, one calculation path. |
| R10 | Scope creep (portal, accounting, bidding bots) delays the core. | High | High | MVP is fixed (section 7); everything else is a listed later phase. |
| R11 | Low-code platform limits (complex approval/inspection logic). | Medium | Medium | Keep a Next.js escape hatch for any screen the low-code tool cannot express (`TECH-STACK.md`). |
| R12 | Key/secret leakage. | Low | Critical | Server-side env vars only; rotate on any exposure; `.gitignore` before first commit. |

---

## 10. Open questions the owner must answer (decisions needed before build)

1. **Data residency (A4)** — is data required to remain in India? This is blocking.
2. **Export control** — will the system ever hold ITAR/EAR/controlled technical data?
3. **Role names (A3)** — confirm the real designations and who holds each.
4. **Approval threshold (A7)** — above what quotation value must management approve?
5. **Currency & tax** — INR only, or multi-currency? GST treatment and place of supply rules.
6. **Existing data (A5)** — what Excel files exist, and can we get exports?
7. **Low-code platform** — approve the recommended tool (or state a preference). See
   `TECH-STACK.md`.
8. **n8n hosting (A10)** — cloud or self-hosted, and in which region?
9. **Inspection authority** — which inspections apply (in-house, DGQA, third-party), and who
   signs off?
10. **Repeat orders** — how is a repeat order actually recognised in this business?

Answering these (especially 1, 2, 5, 7, 8) is the gate between this plan and building the
database.

---

## Decisions log

- 2026-10-07 — PRD drafted as PLAN ONLY from the owner's description. Assumptions A1–A10 and
  open questions 1–10 recorded. No database or application created. Awaiting owner approval.
