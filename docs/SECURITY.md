# SECURITY.md — Ramprasad Defence: Security Model & Runbook

**Scope:** the database layer created in `../supabase/migrations/`. No secrets are stored in
source code; the only secret-bearing file is `.env.local`, which is git-ignored and never
committed.

**Validated:** the RLS, audit and segregation rules below were executed and passed (see
`../../REPORT.md`). Applying them to a live Supabase project still requires that project's URL,
plus enforcing MFA and the Pro-plan settings in the dashboard.

---

## 1. Roles

Seeded in `public.roles` (see `../supabase/seed/0001_roles.sql`):

| code | role |
|---|---|
| `admin` | Administrator — full access |
| `management` | Management / Director — read all, approve |
| `sales` | Sales / Tender Executive |
| `technical` | Technical / Engineering |
| `procurement` | Procurement Officer |
| `stores` | Stores / Receiving |
| `qa` | QA / Inspection |
| `logistics` | Logistics / Dispatch |
| `accounts` | Accounts / Finance |
| `viewer` | Viewer / Guest — read only |

A user can hold several roles; effective permissions are the union, except where the
segregation-of-duties triggers forbid a specific combination.

---

## 2. How access is enforced

1. **Authentication** is Supabase Auth (email + password; MFA available, required for
   `admin`, `management`, `accounts` in production).
2. **Identity mapping:** `public.users` holds our own `id` and the `auth_user_id`. Audit
   columns reference our `id`, not the provider's, so history survives an auth-provider change.
3. **Row Level Security is on for every table.** With RLS enabled and no matching policy, a
   request returns no rows. `anon` (logged out) has no privileges at all.
4. **The helpers** (`app.current_user_id()`, `app.current_roles()`, `app.has_role()`,
   `app.has_any_role()`, `app.is_staff()`, `app.is_admin()`) are `SECURITY DEFINER`, so policy
   evaluation can read `users`/`user_roles` without recursing into RLS.
5. **`service_role`** (the Supabase server key, used by n8n/admin jobs) bypasses RLS. It must
   never be shipped to a browser.

### Write roles (summary)

| Area | Who may write |
|---|---|
| Identity (users, roles, user_roles) | admin |
| Masters (customers, products, oems) | admin, sales, procurement (products also technical) |
| Tenders / requirements / tender notes | admin, sales, technical |
| Opportunities | admin, sales |
| Compliance items | admin, sales, technical, qa |
| Quotations / quotation items | admin, sales |
| Quotation approvals | admin, management |
| Customer orders | admin, sales |
| Purchase requests | admin, sales, procurement |
| Purchase orders | admin, procurement |
| Material receipts | admin, stores |
| PDI records / items | admin, qa |
| Dispatches / delivery documents | admin, logistics |
| Invoices / payments | admin, accounts |
| Warranties | admin, accounts, qa, sales |
| Documents | any staff (classification-restricted read) |
| Tasks | any staff; update limited to assignee / admin / management |
| Notifications | own row; admin/management |
| Audit log | nobody writes (trigger only); tender-related activity readable by all staff |

Every write role is also constrained by the database, not by the screen. A direct API request
that skips the UI still hits RLS.

**Two additions from migration `0014_tender_workflow.sql`:**
- `audit_logs` gained a read policy for **tender-related activity only**
  (`entity_table in ('tenders','tender_notes','tender_requirements')`), so the Tender
  Management "Activity history" works for all staff. Other audit rows remain restricted to
  admin / management / accounts.
- `user_directory` is a **read-only view** exposing only `id`, `full_name`, `designation` of
  active users, for the assignee picker. The strict RLS on `users` is unchanged.

**Added by migration `0015_quotation_module.sql`:**
- A second `audit_logs` read policy for **quotation-related activity**
  (`entity_table in ('quotations','quotation_items','quotation_approvals')`).
- **Approval is restricted:** the `quotation_approvals` write policy allows only admin/management,
  and a unique index permits at most one `approved` step per quotation.
- **Immutability is a security control:** an `approved`/`submitted`/`won`/`lost` quotation and
  its lines cannot be edited by anyone (trigger), so a signed-off price cannot be altered after
  the fact; a revision row is created instead, and every change remains in `audit_logs`.

**Added by migration `0016_procurement_module.sql`:**
- New tables and their write roles: `material_requirements`/`_items` (admin, procurement,
  sales); `oem_rfqs`/`_items` and `oem_quotations`/`_items` (admin, procurement);
  `purchase_approvals` (admin, management only); `procurement_documents` (admin, procurement,
  qa, stores). All readable by staff.
- **Purchase approval is restricted** to admin/management, and a unique index permits at most
  one `approved` step per purchase order.
- **Compliance documents** are stored in the private bucket and linked via
  `procurement_documents`, with an expiry date for alerting.
- A procurement-activity `audit_logs` read policy lets staff see the procurement history.

**Management dashboard access:**
- `/dashboard` and every drill-down page are restricted to the **admin** and **management**
  roles (checked on the server before any query). Any other signed-in user sees a permission
  message, not the data.
- Every figure is computed with the signed-in user's session, so **Row Level Security still
  applies** — the dashboard can only show rows the user is permitted to read. It is a read-only
  view and adds no new tables or write paths.





---

## 3. Defence-specific data controls

1. **Classification on every document:** `unclassified | internal | confidential | controlled |
   itar_ear`. A user without `admin`/`management`/`technical`/`qa` cannot read
   `controlled`/`itar_ear` rows — verified by test.
2. **Export-control caveat (`itar_ear`):** storing ITAR/EAR-controlled technical data may
   require controls beyond this stack. Get legal sign-off before classifying any row
   `itar_ear`, and if required, keep such files out of the system entirely (PRD R2).
3. **Data residency:** unresolved (PRD §10 Q1). If defence data must stay in India, choose the
   region before deployment; if no compliant region is available, the hosting vendor must be
   reconsidered. The schema itself is unaffected.
4. **n8n must not become a data leak:** self-host n8n in the approved region and send only
   minimal notification text plus record pointers, never attachments containing controlled data.

---

## 4. Integrity rules that are also security controls

- **Segregation of duties:** the invoice creator cannot record that invoice's payment; the PO
  creator cannot receive that PO's goods. Enforced by trigger (`check_violation`).
- **PDI gate:** nothing can be dispatched until a passed PDI exists for its order line.
  Enforced by trigger — a bad dispatch cannot be created even by the correct role.
- **Paid-invoice lock:** once `paid`/`void`, an invoice's financial fields cannot be changed.
- **Derived money:** line totals are `GENERATED`; header totals are recalculated from lines, so
  a forged total cannot be saved.
- **Append-only audit:** `audit_logs` has no insert/update/delete policy; rows are written only
  by the `SECURITY DEFINER` audit trigger. Verified by test.

---

## 5. Secrets handling

- Secrets live only in `.env.local` (local) and the hosting provider's environment settings
  (production). `.env.example` lists **names only**, never values.
- The repo `.gitignore` excludes `.env`, `.env.*`, `*.pem`, `*.key`, plus this project's
  `.env.local`.
- Supabase **anon** key may reach the browser; the **service_role** key must not.
- Rotate any key that is ever pasted into chat, committed, or shipped to a browser.

---

## 6. Production settings checklist (dashboard, not code)

- [ ] Supabase project in the approved region.
- [ ] MFA enforced for `admin`, `management`, `accounts`.
- [ ] Session timeout configured.
- [ ] Leaked-password protection enabled.
- [ ] Supabase Pro (automatic daily backups) before real money data.
- [ ] Storage buckets **private**; access only via signed URLs.
- [ ] n8n connected with a restricted role/key, not the service key.
- [ ] Auth and database logs retained and reviewed.
- [ ] Restore-from-backup rehearsed once.

---

## 7. What is verified vs not

- **Verified (executed, 32/32 checks):** RLS default-deny; role-scoped reads and writes;
  controlled-document restriction; append-only audit; segregation of duties; PDI gate; paid
  invoice lock; derived totals/quantities; `updated_at` maintenance.
- **Not yet verified (UNVERIFIED):** application against a live Supabase project; MFA and
  session settings; private storage bucket policies; n8n connectivity; backup/restore drill.
  These require live credentials and are the next phase after this schema is approved.
