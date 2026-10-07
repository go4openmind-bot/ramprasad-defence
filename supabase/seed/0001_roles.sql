-- =============================================================================
-- seed/0001_seed.sql
-- Baseline reference data. Safe to re-run (idempotent).
-- =============================================================================

-- The ten roles used by all RLS policies. Keep these codes in sync with
-- app.is_staff() in 0003_security_helpers.sql.
insert into public.roles (code, name, description) values
  ('admin',       'Administrator',            'Full access: users, roles, settings and all data.'),
  ('management',  'Management / Director',    'Read all; approve quotations and purchase orders.'),
  ('sales',       'Sales / Tender Executive', 'Tenders, opportunities, quotations, customer orders.'),
  ('technical',   'Technical / Engineering',  'Technical requirements, feasibility, product specifications.'),
  ('procurement', 'Procurement Officer',      'OEM contacts, RFQs, purchase orders, supplier prices.'),
  ('stores',      'Stores / Receiving',       'Goods receipt against purchase orders.'),
  ('qa',          'QA / Inspection',          'PDI and inspection records, certificates, compliance.'),
  ('logistics',   'Logistics / Dispatch',     'Dispatches, delivery documents, proof of delivery.'),
  ('accounts',    'Accounts / Finance',       'Invoices, payments, receivables ageing.'),
  ('viewer',      'Viewer / Guest',           'Read-only access to business data.')
on conflict (code) do update
  set name = excluded.name,
      description = excluded.description,
      updated_at = now();
