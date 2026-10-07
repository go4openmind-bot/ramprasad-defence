# Tender Management app — how to run it

This is the Tender Management module. It is a small web app (Next.js) that talks to the
Supabase database built in `../supabase/migrations`. You do not need to write code to run it.

## What it does

- Tender list with **search** and **filters** (status, priority, assignee, deadline).
- **Create / edit** a tender (required fields are enforced).
- **Tender detail** page with the 13-stage **status pipeline**, **closing date**, **priority**,
  **assign employee**, **requirement section**, **notes**, **tasks**, **document upload** and
  **activity history**.
- **Deadline indicators:** green = normal, yellow = approaching (within 7 days),
  red = overdue or high risk (high/critical priority near its date).
- **Quotations:** create a quotation linked to a customer, tender, OEM, product and tender
  requirement; add multiple product lines with purchase, logistics and other cost, a selling
  price, discount and GST; automatic cost, line total and margin calculation; technical
  compliance per line; an approval workflow (management approves); revision history — an
  approved quotation is never overwritten, a revision is created instead; PDF download;
  follow-up tasks; and full activity history.
- **Procurement:** customer order → material requirement → purchase request → OEM RFQ → OEM
  quotation → OEM selection → purchase approval → purchase order → expected delivery → material
  receipt → PDI → ready for dispatch. Tracks OEM, product, quantity, purchase price, expected
  and actual delivery, payment terms, warranty, compliance documents and status, and shows
  **automatic delivery-risk indicators** (green/yellow/red) when OEM delivery may delay the
  customer delivery.
- **Management dashboard** (`/dashboard`, for management and administrators only): 16 live
  numbers — active/closing-soon/submitted/won/lost tenders, active customer orders, orders at
  delivery risk, delayed orders, pending OEM deliveries, pending PDI, pending dispatch,
  outstanding and overdue payments, monthly sales, gross margin and OEM performance. **Every
  number drills down to the underlying records.**

## One-time setup

1. **Install Node.js 18 or newer** (https://nodejs.org).
2. **Create the database** (if not already done): in the `Ramprasad-Defence Project` folder, run
   the migrations in `supabase/migrations` against your Supabase project (or paste them in the
   Supabase SQL editor in filename order).
3. **Create a private Storage bucket** named `documents` in Supabase Storage.
4. **Create the first user:**
   - In Supabase → Authentication → Users, add a user with an email and password.
   - Then run this in the SQL editor (replace the email):
     ```sql
     insert into public.users (auth_user_id, full_name, email)
     values ((select id from auth.users where email = 'you@example.com'), 'Your Name', 'you@example.com');

     insert into public.user_roles (user_id, role_code)
     select id, 'admin' from public.users where email = 'you@example.com';
     ```
   - Add more people the same way, granting `sales`, `technical`, `procurement`, etc.
5. **Configure the app:** copy `app/.env.example` to `app/.env.local` and fill in:
   - `SUPABASE_URL` — your project URL (server-side)
   - `SUPABASE_PUBLISHABLE_KEY` — the **publishable / anon** key (server-side)
   - `SUPABASE_DOCUMENTS_BUCKET=documents`
   - Leave `SUPABASE_SECRET_KEY` blank unless a trusted admin script needs it. It is server-only
     and is **not** used by the running app.
6. **Install and start:**
   ```
   cd app
   npm install
   npm run dev
   ```
   Open the address it prints (usually http://localhost:3000) and sign in.

## Checks you can run yourself

```
npm test      # logic tests for deadlines, quotations, procurement risk and the dashboard
npm run build # compiles the whole app and type-checks it

# Connection test (prints only SUCCESS/FAILED, never any key):
node --env-file=.env.local scripts/check-supabase.mjs
```

## Publishing (optional, later)

Deploy `app/` to Vercel (import the folder as the project). Set the same environment variables
in the Vercel project (`SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `SUPABASE_DOCUMENTS_BUCKET`;
and `SUPABASE_SECRET_KEY` only if an admin script needs it, marked sensitive). The running app
uses only the publishable key; Row Level Security protects the data.

## Security notes

- `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` are **server-side** names (no `NEXT_PUBLIC_`
  prefix), because this app has no browser-side Supabase client.
- The Supabase **secret / service_role** key is server-side only: never `NEXT_PUBLIC_`, never in
  browser code, never committed. `app/.env.local` is git-ignored.
- Every table is protected by Row Level Security (see `../docs/SECURITY.md`).
- Document uploads go to a **private** bucket; downloads use short-lived signed links.
