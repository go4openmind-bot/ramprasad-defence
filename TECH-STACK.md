# TECH-STACK — Ramprasad Defence: Defence Contract & Supply Management System

**Status: DRAFT — PLAN ONLY.** This document answers one question: what do we build it with,
and why that? It is written for review before any component is created.

**Inputs:** `PRD.md` (requirements, roles, workflow, MVP, risks A1–A10, R1–R12).

**How to read every entry:** each choice is paired with *the constraint that forced it* and
*what was rejected and why*, so the decision is not re-argued in three months.

**Fixed by the owner (not open for re-litigation):**
- **Supabase** for database, authentication and storage.
- **n8n** for workflow automation.
- **Low-code / admin UI** wherever practical.
- **VS Code** as the development environment.

---

## 0. Design principles

1. **Build one spine, then thin workflows on it.** Tender → quote → order → procure → receive →
   inspect → dispatch → invoice → payment is one chain over shared data. Not nine tools.
2. **Managed services, no infrastructure to patch.** There is no ops team.
3. **Regulated data changes the rules.** Defence/export-controlled data may restrict *where*
   components run (PRD R1, R2, R3). Resolve residency before building.
4. **One calc path, exact money.** All money is `numeric` in Postgres, totalled server-side,
   computed once. No browser totals, no second copy.
5. **Validate at the edge.** Every write rejects missing required fields with a reason and
   saves nothing (`AGENTS.md` §3).
6. **Permissions live in the database**, not in the screen. RLS is the guard; the UI is a
   convenience.

---

## 1. System architecture (one picture)

```
        ┌────────────────────────────────────────────────────────────────┐
        │  USERS (browser, desktop/laptop)                                │
        │  admin · management · sales · technical · procurement ·         │
        │  stores · qa · logistics · accounts · viewer                    │
        └───────────────────────────┬────────────────────────────────────┘
                                    │ HTTPS
                 ┌──────────────────┴───────────────────┐
                 │                                      │
        ┌────────▼─────────┐                 ┌──────────▼───────────┐
        │  ADMIN UI        │                 │  SUPABASE AUTH       │
        │  (low-code app:  │                 │  (email+pw, MFA,     │
        │  Appsmith or     │◄───────────────►│   sessions, roles)   │
        │  Budibase)       │   JWT           └──────────────────────┘
        │  - forms         │
        │  - lists         │                 ┌──────────────────────┐
        │  - dashboards    │◄───────────────►│  SUPABASE POSTGRES   │
        │  - approvals     │   REST/SQL,     │  - all tables        │
        └──────────────────┘   RLS enforced │  - RLS policies      │
                 ▲                            │  - audit_log         │
                 │                            │  - status_events     │
                 │                            └──────────┬───────────┘
                 │                                       │
        ┌────────┴─────────┐                 ┌───────────▼───────────┐
        │  n8n (workflows) │                 │  SUPABASE STORAGE     │
        │  - due-date      │                 │  private buckets:     │
        │    reminders     │                 │  tender docs, quotes, │
        │  - approval      │                 │  POs, inspection      │
        │    notifications │                 │  certs, invoices      │
        │  - escalation    │                 │  (signed URLs only)   │
        │  - PDF/mail      │                 └───────────────────────┘
        └────────┬─────────┘
                 │ SMTP / API
        ┌────────▼─────────┐
        │  EMAIL / ALERTS  │
        └──────────────────┘

     Escalation path (any screen the low-code tool cannot express):
        ┌──────────────────────────────────────────┐
        │  Next.js "escape hatch" (optional later)  │
        │  deployed on Vercel, same Postgres,       │
        │  same RLS, same auth                      │
        └──────────────────────────────────────────┘
```

**The one rule:** the low-code UI, the escape-hatch app and n8n all talk to the **same
Postgres** and are subject to the **same RLS**. There is never a second copy of the data and
never a component that bypasses permissions.

---

## 2. Layer-by-layer decisions

### 2.1 Database — Supabase Postgres
- **Chosen:** Supabase-managed PostgreSQL.
- **Constraint that forced it:** the product needs relational integrity (a PO references a
  quotation references a tender), exact decimal money, transactional writes, and an auditable
  append-only history. It also *must* enforce per-role row access where the data lives.
- **Rejected:** SQLite/Turso (weak multi-user story), MySQL/PlanetScale (no advantage),
  MongoDB/Firestore (weaker exact aggregation and audit), self-hosted Postgres (infra to
  patch, and residency is a separate decision — see R1), spreadsheets-as-database (the problem
  being replaced).
- **MVP:** Supabase Free. **Production:** Supabase Pro (backups + no inactivity pause).
- **Region:** must be chosen for the residency answer (A4). `ASSUMPTION TECH-1`: pick the
  closest permitted region; if India-only residency is mandatory this is the first thing to
  re-evaluate.

### 2.2 Authentication — Supabase Auth
- **Chosen:** Supabase Auth (email + password, MFA, magic link optional), with role and
  company scope held in our own `user_roles` table and enforced by RLS.
- **Constraint that forced it:** individual logins, MFA for sensitive roles, and an audit
  trail that must name a real actor on every change.
- **Rejected:** Auth0/Clerk/WorkOS (a second paid vendor for a solved problem), rolling our own
  password storage (never), Google-only (assumes Workspace), corporate SSO (no requirement).
- **Lock-in mitigation:** audit rows reference our own `users.id`, not the provider's ID, so
  the provider can be replaced without orphaning history.

### 2.3 Storage — Supabase Storage
- **Chosen:** private Storage buckets, one per document family, access via short-lived signed
  URLs for authenticated+authorized users.
- **Constraint that forced it:** tender docs, quotes, POs, inspection certificates and invoices
  are evidence; they must be retrievable with the record and must not be publicly reachable.
- **Rejected:** public buckets (a leaked URL is a data leak), storing files in the database
  (bloats it, no CDN), a separate file vendor (unnecessary).
- **Classification:** each document carries a `classification` field; `controlled`/`itar_ear`
  restricted to named roles (PRD R2).

### 2.4 Admin UI — low-code (primary), Next.js (escape hatch)

> **2026-10-07 — DECISION TAKEN for the Tender Management module: the Next.js escape hatch
> was used.** Reason: no low-code platform (Appsmith/Budibase) is connected in this
> environment and no live Supabase credentials exist, so the low-code path could not be built
> or verified. The Next.js app is version-controlled and provably builds and passes tests.
> **This does not change the database or RLS** — the data layer is identical, so a low-code UI
> can still be added alongside or replace this app later. The low-code analysis below stands
> for the remaining modules.
- **Chosen (recommended):** a low-code internal-tool builder on top of Supabase Postgres.
  - **Primary recommendation:** **Appsmith** — mature, role-based access, good forms, tables,
    approvals, PDF/report widgets, connects directly to Postgres, open-source self-host option
    (useful if data must stay in-region, R1/R3).
  - **Alternative:** **Budibase** — more beginner-friendly, also connects to Postgres, self-host
    and cloud.
  - **Spreadsheet-style alternative:** **NocoDB** — closest feel to Excel (easiest migration
    from the current workflow) but weaker at complex approval/inspection logic.
- **Constraint that forced a low-code approach:** the owner is a non-programmer and the
  requirement is explicit ("low-code/admin UI wherever practical"); the work is mostly forms,
  lists, dashboards and approvals, which low-code tools do well.
- **Rejected as the *only* UI:** pure Supabase Studio (not a business UI), pure Excel/NocoDB
  (cannot enforce the workflow gates in PRD §5).
- **Escape hatch:** **Next.js on Vercel**, optional, for any screen the low-code tool cannot
  express (complex PDI workflow, customer portal, custom PDF). Same Postgres, same auth, same
  RLS. This is added only if needed, not up front.

### 2.5 Workflow automation — n8n
- **Chosen:** n8n workflows for time-based and event-based jobs: bid-due and corrigendum
  reminders, RFQ follow-ups, approval notifications, PO delivery overdue, inspection-failed
  alerts, invoice overdue, weekly digest.
- **Constraint that forced it:** many requirements are "do X when date Y approaches or status
  Z changes" (PRD §5 stage gates, MVP alerts). These are automation, not UI.
- **Rejected:** cron scripts (no visibility for a non-programmer), Supabase pg_cron only
  (capable but not as inspectable), Zapier/Make (n8n is fixed by the owner and self-hostable).
- **Data-path caution (R3):** n8n must not be a place controlled data leaks. Prefer
  **self-hosted n8n in the approved region**, and have workflows send **minimal notification
  text and record pointers**, never attachments with controlled content.
- **Database access:** n8n uses a restricted Postgres role / scoped API key, not the master
  key. It writes only the tables its workflows need.

### 2.6 Development environment — VS Code
- **Chosen:** VS Code + Kilo Code, with Supabase CLI for migrations and a Git repository.
- **Constraint that forced it:** the owner fixed VS Code; migrations-as-code and version
  control make changes reviewable and reversible.
- **Rejected:** dashboard-only database edits (no history, hard to review, easy to break).

### 2.7 Environment separation
- **Chosen:** at least two Supabase projects — **dev** and **prod** — with identical migrations.
  Low-code app and n8n have separate connections per environment.
- **Constraint:** never test workflow changes against live tender data.

---

## 3. Data flow (a write, end to end)

1. User acts in the low-code UI (e.g. records supplier receipt).
2. The app sends the write to Supabase with the user's JWT.
3. **RLS checks** the user's role and ownership; a denied write returns an error, not a row.
4. **Validation** rejects missing required fields with a reason (`AGENTS.md` §3).
5. The write commits; a trigger writes an `audit_log` row and, for status changes, a
   `status_events` row (actor + from/to + time).
6. **n8n** is notified (webhook/DB trigger) and runs the relevant workflow (alert, reminder).
7. The UI re-reads and shows the new state.

Money totals are always computed by a **single server-side aggregate** over the same rows the
UI shows — never in the browser, never cached.

---

## 4. MVP vs production

| Layer | MVP | Production | Change type |
|---|---|---|---|
| Database | Supabase Free | Supabase Pro | Plan switch |
| Backups | None on Free | Daily, 7-day retention (Pro) | Config switch |
| Inactivity pause | Pauses after ~1 week idle | Never (Pro) | Config switch |
| Auth | Email+pw, individual logins | + MFA enforced for admin/management/accounts, session timeouts | Config switch |
| Storage | Private buckets, signed URLs | Same | No change |
| Admin UI | Appsmith (or Budibase), cloud or self-host | Same, self-hosted if residency requires | Hosting switch |
| Automation | n8n self-hosted, minimal payloads | Same | No change |
| Escape hatch app | Not built | Next.js on Vercel, only if needed | Additive |
| Region | Must be chosen | Same | Decision, not a switch |

**The one upgrade forced by data, not traffic:** Supabase Free has **no automatic backups**.
The day this database holds the only copy of live order/payment data, move to Pro.

---

## 5. Cost (order of magnitude)

| Line | MVP | Production |
|---|---|---|
| Supabase | $0 (Free) | ~$25/mo (Pro) |
| Admin UI (Appsmith/Budibase) | $0 self-host / small cloud | small |
| n8n | $0 self-host | hosting only |
| Hosting (escape-hatch Next.js, if used) | $0 | ~$20/mo |
| Domain / email | — | ~$10–15/yr |
| **Floor** | **~$0** | **~$45–60/mo** |

Exact vendor prices are `UNVERIFIED` and must be re-checked on the day of commitment.

---

## 6. What would change these choices

| Trigger | Impact |
|---|---|
| India-only data residency is mandatory (A4) | Supabase region invalid; evaluate self-hosted/India Postgres. **Stack-level re-evaluation.** |
| ITAR/EAR-controlled data must be stored (R2) | Requires access controls beyond this stack; may exclude such files from the system entirely. |
| Low-code tool cannot express PDI/approval logic | Build that screen in the Next.js escape hatch. |
| Multi-company / multi-branch (A1 changes) | Every table and RLS policy changes shape. |
| Government portal API access becomes available | Separate integration project; n8n is the natural place to land it. |

---

## 7. The decision most expensive to reverse

**Making this database the single source of truth for the tender-to-payment chain** — rather
than a view that mirrors the Excel files — and encoding that in the schema and RLS.

In six months it holds every tender, quote, PO, inspection, dispatch, invoice and payment, plus
the only trustworthy audit trail. Reversing it means reconciling two systems that have drifted,
deciding retroactively which history is real, and rebuilding trust. The UI and the automation
are replaceable; this is not.

**Mitigation applied now:** decide the open questions in `PRD.md` §10 (residency, roles,
approval threshold, currency) **before** the first migration is written.

---

## Decisions log

- 2026-10-07 — Tech stack drafted as PLAN ONLY. Supabase (DB/Auth/Storage) + n8n + low-code UI
  (Appsmith recommended, Budibase/NocoDB alternatives) + VS Code, with an optional Next.js
  escape hatch. Region decision and cost figures flagged as unresolved/`UNVERIFIED`.
