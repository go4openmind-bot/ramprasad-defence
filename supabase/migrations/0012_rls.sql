-- =============================================================================
-- 0012_rls.sql
-- Row Level Security: default deny, role-based access, append-only audit.
-- Assumes the Supabase roles anon, authenticated and service_role already exist.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Privileges. RLS is the row-level guard; these are the table-level grants.
-- anon (logged out) gets nothing. authenticated gets the baseline, then RLS
-- decides row by row. service_role bypasses RLS (Supabase's server key).
-- -----------------------------------------------------------------------------
grant usage on schema public to authenticated, service_role;
revoke all on all tables in schema public from anon;
revoke all on all functions in schema app from public, anon;
grant execute on all functions in schema app to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant all on all tables in schema public to service_role;
grant usage, select on all sequences in schema public to authenticated, service_role;
alter default privileges in schema public grant select, insert, update, delete on tables to authenticated;
alter default privileges in schema public grant all on tables to service_role;

-- -----------------------------------------------------------------------------
-- Enable RLS on every table. With RLS on and no matching policy: no access.
-- -----------------------------------------------------------------------------
alter table public.users                 enable row level security;
alter table public.roles                 enable row level security;
alter table public.user_roles            enable row level security;
alter table public.customers             enable row level security;
alter table public.customer_contacts     enable row level security;
alter table public.products              enable row level security;
alter table public.product_specifications enable row level security;
alter table public.oems                  enable row level security;
alter table public.oem_contacts          enable row level security;
alter table public.oem_products          enable row level security;
alter table public.oem_price_history     enable row level security;
alter table public.documents             enable row level security;
alter table public.tenders               enable row level security;
alter table public.tender_documents      enable row level security;
alter table public.tender_requirements   enable row level security;
alter table public.opportunities         enable row level security;
alter table public.requirements          enable row level security;
alter table public.compliance_items      enable row level security;
alter table public.quotations            enable row level security;
alter table public.quotation_items       enable row level security;
alter table public.quotation_approvals   enable row level security;
alter table public.customer_orders       enable row level security;
alter table public.order_items           enable row level security;
alter table public.purchase_requests     enable row level security;
alter table public.purchase_request_items enable row level security;
alter table public.purchase_orders       enable row level security;
alter table public.purchase_order_items  enable row level security;
alter table public.material_receipts     enable row level security;
alter table public.material_receipt_items enable row level security;
alter table public.pdi_records           enable row level security;
alter table public.pdi_items             enable row level security;
alter table public.dispatches            enable row level security;
alter table public.dispatch_items        enable row level security;
alter table public.delivery_documents    enable row level security;
alter table public.invoices              enable row level security;
alter table public.invoice_items         enable row level security;
alter table public.payments              enable row level security;
alter table public.warranties            enable row level security;
alter table public.tasks                 enable row level security;
alter table public.notifications         enable row level security;
alter table public.audit_logs            enable row level security;

-- =============================================================================
-- IDENTITY / ACCESS
-- =============================================================================
create policy users_select on public.users for select to authenticated
  using (id = app.current_user_id() or app.has_any_role(array['admin','management']));
create policy users_insert on public.users for insert to authenticated
  with check (app.is_admin());
create policy users_update on public.users for update to authenticated
  using (app.is_admin()) with check (app.is_admin());
create policy users_delete on public.users for delete to authenticated
  using (app.is_admin());

create policy roles_select on public.roles for select to authenticated
  using (app.is_staff());
create policy roles_insert on public.roles for insert to authenticated
  with check (app.is_admin());
create policy roles_update on public.roles for update to authenticated
  using (app.is_admin()) with check (app.is_admin());
create policy roles_delete on public.roles for delete to authenticated
  using (app.is_admin());

create policy user_roles_select on public.user_roles for select to authenticated
  using (user_id = app.current_user_id() or app.has_any_role(array['admin','management']));
create policy user_roles_insert on public.user_roles for insert to authenticated
  with check (app.is_admin());
create policy user_roles_update on public.user_roles for update to authenticated
  using (app.is_admin()) with check (app.is_admin());
create policy user_roles_delete on public.user_roles for delete to authenticated
  using (app.is_admin());

-- =============================================================================
-- MASTERS  (read: all staff)  (write: admin, sales, procurement)
-- =============================================================================
create policy customers_select on public.customers for select to authenticated using (app.is_staff());
create policy customers_insert on public.customers for insert to authenticated with check (app.has_any_role(array['admin','sales','procurement']));
create policy customers_update on public.customers for update to authenticated using (app.has_any_role(array['admin','sales','procurement'])) with check (app.has_any_role(array['admin','sales','procurement']));
create policy customers_delete on public.customers for delete to authenticated using (app.is_admin());

create policy customer_contacts_select on public.customer_contacts for select to authenticated using (app.is_staff());
create policy customer_contacts_insert on public.customer_contacts for insert to authenticated with check (app.has_any_role(array['admin','sales','procurement']));
create policy customer_contacts_update on public.customer_contacts for update to authenticated using (app.has_any_role(array['admin','sales','procurement'])) with check (app.has_any_role(array['admin','sales','procurement']));
create policy customer_contacts_delete on public.customer_contacts for delete to authenticated using (app.is_admin());

create policy products_select on public.products for select to authenticated using (app.is_staff());
create policy products_insert on public.products for insert to authenticated with check (app.has_any_role(array['admin','sales','procurement','technical']));
create policy products_update on public.products for update to authenticated using (app.has_any_role(array['admin','sales','procurement','technical'])) with check (app.has_any_role(array['admin','sales','procurement','technical']));
create policy products_delete on public.products for delete to authenticated using (app.is_admin());

create policy product_specifications_select on public.product_specifications for select to authenticated using (app.is_staff());
create policy product_specifications_insert on public.product_specifications for insert to authenticated with check (app.has_any_role(array['admin','technical','procurement']));
create policy product_specifications_update on public.product_specifications for update to authenticated using (app.has_any_role(array['admin','technical','procurement'])) with check (app.has_any_role(array['admin','technical','procurement']));
create policy product_specifications_delete on public.product_specifications for delete to authenticated using (app.is_admin());

create policy oems_select on public.oems for select to authenticated using (app.is_staff());
create policy oems_insert on public.oems for insert to authenticated with check (app.has_any_role(array['admin','procurement']));
create policy oems_update on public.oems for update to authenticated using (app.has_any_role(array['admin','procurement'])) with check (app.has_any_role(array['admin','procurement']));
create policy oems_delete on public.oems for delete to authenticated using (app.is_admin());

create policy oem_contacts_select on public.oem_contacts for select to authenticated using (app.is_staff());
create policy oem_contacts_insert on public.oem_contacts for insert to authenticated with check (app.has_any_role(array['admin','procurement']));
create policy oem_contacts_update on public.oem_contacts for update to authenticated using (app.has_any_role(array['admin','procurement'])) with check (app.has_any_role(array['admin','procurement']));
create policy oem_contacts_delete on public.oem_contacts for delete to authenticated using (app.is_admin());

create policy oem_products_select on public.oem_products for select to authenticated using (app.is_staff());
create policy oem_products_insert on public.oem_products for insert to authenticated with check (app.has_any_role(array['admin','procurement','technical']));
create policy oem_products_update on public.oem_products for update to authenticated using (app.has_any_role(array['admin','procurement','technical'])) with check (app.has_any_role(array['admin','procurement','technical']));
create policy oem_products_delete on public.oem_products for delete to authenticated using (app.is_admin());

create policy oem_price_history_select on public.oem_price_history for select to authenticated using (app.is_staff());
create policy oem_price_history_insert on public.oem_price_history for insert to authenticated with check (app.has_any_role(array['admin','procurement','sales']));
create policy oem_price_history_update on public.oem_price_history for update to authenticated using (app.has_any_role(array['admin','procurement','sales'])) with check (app.has_any_role(array['admin','procurement','sales']));
create policy oem_price_history_delete on public.oem_price_history for delete to authenticated using (app.is_admin());

-- =============================================================================
-- DOCUMENTS  (read: staff, but controlled/itar restricted)
-- =============================================================================
create policy documents_select on public.documents for select to authenticated
  using (
    app.is_staff()
    and (
      classification in ('unclassified','internal','confidential')
      or app.has_any_role(array['admin','management','technical','qa'])
    )
  );
create policy documents_insert on public.documents for insert to authenticated
  with check (app.is_staff());
create policy documents_update on public.documents for update to authenticated
  using (app.is_staff()) with check (app.is_staff());
create policy documents_delete on public.documents for delete to authenticated
  using (app.is_admin());

-- =============================================================================
-- TENDERS / OPPORTUNITIES
-- =============================================================================
create policy tenders_select on public.tenders for select to authenticated using (app.is_staff());
create policy tenders_insert on public.tenders for insert to authenticated with check (app.has_any_role(array['admin','sales']));
create policy tenders_update on public.tenders for update to authenticated using (app.has_any_role(array['admin','sales','technical'])) with check (app.has_any_role(array['admin','sales','technical']));
create policy tenders_delete on public.tenders for delete to authenticated using (app.is_admin());

create policy tender_documents_select on public.tender_documents for select to authenticated using (app.is_staff());
create policy tender_documents_insert on public.tender_documents for insert to authenticated with check (app.has_any_role(array['admin','sales','technical']));
create policy tender_documents_update on public.tender_documents for update to authenticated using (app.has_any_role(array['admin','sales','technical'])) with check (app.has_any_role(array['admin','sales','technical']));
create policy tender_documents_delete on public.tender_documents for delete to authenticated using (app.is_admin());

create policy tender_requirements_select on public.tender_requirements for select to authenticated using (app.is_staff());
create policy tender_requirements_insert on public.tender_requirements for insert to authenticated with check (app.has_any_role(array['admin','sales','technical']));
create policy tender_requirements_update on public.tender_requirements for update to authenticated using (app.has_any_role(array['admin','sales','technical'])) with check (app.has_any_role(array['admin','sales','technical']));
create policy tender_requirements_delete on public.tender_requirements for delete to authenticated using (app.is_admin());

create policy opportunities_select on public.opportunities for select to authenticated using (app.is_staff());
create policy opportunities_insert on public.opportunities for insert to authenticated with check (app.has_any_role(array['admin','sales']));
create policy opportunities_update on public.opportunities for update to authenticated using (app.has_any_role(array['admin','sales'])) with check (app.has_any_role(array['admin','sales']));
create policy opportunities_delete on public.opportunities for delete to authenticated using (app.is_admin());

create policy requirements_select on public.requirements for select to authenticated using (app.is_staff());
create policy requirements_insert on public.requirements for insert to authenticated with check (app.has_any_role(array['admin','sales','technical']));
create policy requirements_update on public.requirements for update to authenticated using (app.has_any_role(array['admin','sales','technical'])) with check (app.has_any_role(array['admin','sales','technical']));
create policy requirements_delete on public.requirements for delete to authenticated using (app.is_admin());

create policy compliance_items_select on public.compliance_items for select to authenticated using (app.is_staff());
create policy compliance_items_insert on public.compliance_items for insert to authenticated with check (app.has_any_role(array['admin','sales','technical','qa']));
create policy compliance_items_update on public.compliance_items for update to authenticated using (app.has_any_role(array['admin','sales','technical','qa'])) with check (app.has_any_role(array['admin','sales','technical','qa']));
create policy compliance_items_delete on public.compliance_items for delete to authenticated using (app.is_admin());

-- =============================================================================
-- QUOTATIONS  (approval is management/admin only)
-- =============================================================================
create policy quotations_select on public.quotations for select to authenticated using (app.is_staff());
create policy quotations_insert on public.quotations for insert to authenticated with check (app.has_any_role(array['admin','sales']));
create policy quotations_update on public.quotations for update to authenticated using (app.has_any_role(array['admin','sales','management'])) with check (app.has_any_role(array['admin','sales','management']));
create policy quotations_delete on public.quotations for delete to authenticated using (app.is_admin());

create policy quotation_items_select on public.quotation_items for select to authenticated using (app.is_staff());
create policy quotation_items_insert on public.quotation_items for insert to authenticated with check (app.has_any_role(array['admin','sales']));
create policy quotation_items_update on public.quotation_items for update to authenticated using (app.has_any_role(array['admin','sales'])) with check (app.has_any_role(array['admin','sales']));
create policy quotation_items_delete on public.quotation_items for delete to authenticated using (app.is_admin());

create policy quotation_approvals_select on public.quotation_approvals for select to authenticated using (app.is_staff());
create policy quotation_approvals_insert on public.quotation_approvals for insert to authenticated with check (app.has_any_role(array['admin','management']));
create policy quotation_approvals_update on public.quotation_approvals for update to authenticated using (app.has_any_role(array['admin','management'])) with check (app.has_any_role(array['admin','management']));
create policy quotation_approvals_delete on public.quotation_approvals for delete to authenticated using (app.is_admin());

-- =============================================================================
-- CUSTOMER ORDERS
-- =============================================================================
create policy customer_orders_select on public.customer_orders for select to authenticated using (app.is_staff());
create policy customer_orders_insert on public.customer_orders for insert to authenticated with check (app.has_any_role(array['admin','sales']));
create policy customer_orders_update on public.customer_orders for update to authenticated using (app.has_any_role(array['admin','sales'])) with check (app.has_any_role(array['admin','sales']));
create policy customer_orders_delete on public.customer_orders for delete to authenticated using (app.is_admin());

create policy order_items_select on public.order_items for select to authenticated using (app.is_staff());
create policy order_items_insert on public.order_items for insert to authenticated with check (app.has_any_role(array['admin','sales']));
create policy order_items_update on public.order_items for update to authenticated using (app.has_any_role(array['admin','sales'])) with check (app.has_any_role(array['admin','sales']));
create policy order_items_delete on public.order_items for delete to authenticated using (app.is_admin());

-- =============================================================================
-- PROCUREMENT
-- =============================================================================
create policy purchase_requests_select on public.purchase_requests for select to authenticated using (app.is_staff());
create policy purchase_requests_insert on public.purchase_requests for insert to authenticated with check (app.has_any_role(array['admin','sales','procurement']));
create policy purchase_requests_update on public.purchase_requests for update to authenticated using (app.has_any_role(array['admin','sales','procurement'])) with check (app.has_any_role(array['admin','sales','procurement']));
create policy purchase_requests_delete on public.purchase_requests for delete to authenticated using (app.is_admin());

create policy purchase_request_items_select on public.purchase_request_items for select to authenticated using (app.is_staff());
create policy purchase_request_items_insert on public.purchase_request_items for insert to authenticated with check (app.has_any_role(array['admin','sales','procurement']));
create policy purchase_request_items_update on public.purchase_request_items for update to authenticated using (app.has_any_role(array['admin','sales','procurement'])) with check (app.has_any_role(array['admin','sales','procurement']));
create policy purchase_request_items_delete on public.purchase_request_items for delete to authenticated using (app.is_admin());

create policy purchase_orders_select on public.purchase_orders for select to authenticated using (app.is_staff());
create policy purchase_orders_insert on public.purchase_orders for insert to authenticated with check (app.has_any_role(array['admin','procurement']));
create policy purchase_orders_update on public.purchase_orders for update to authenticated using (app.has_any_role(array['admin','procurement','management'])) with check (app.has_any_role(array['admin','procurement','management']));
create policy purchase_orders_delete on public.purchase_orders for delete to authenticated using (app.is_admin());

create policy purchase_order_items_select on public.purchase_order_items for select to authenticated using (app.is_staff());
create policy purchase_order_items_insert on public.purchase_order_items for insert to authenticated with check (app.has_any_role(array['admin','procurement']));
create policy purchase_order_items_update on public.purchase_order_items for update to authenticated using (app.has_any_role(array['admin','procurement'])) with check (app.has_any_role(array['admin','procurement']));
create policy purchase_order_items_delete on public.purchase_order_items for delete to authenticated using (app.is_admin());

-- =============================================================================
-- RECEIPTS / INSPECTION
-- =============================================================================
create policy material_receipts_select on public.material_receipts for select to authenticated using (app.is_staff());
create policy material_receipts_insert on public.material_receipts for insert to authenticated with check (app.has_any_role(array['admin','stores']));
create policy material_receipts_update on public.material_receipts for update to authenticated using (app.has_any_role(array['admin','stores'])) with check (app.has_any_role(array['admin','stores']));
create policy material_receipts_delete on public.material_receipts for delete to authenticated using (app.is_admin());

create policy material_receipt_items_select on public.material_receipt_items for select to authenticated using (app.is_staff());
create policy material_receipt_items_insert on public.material_receipt_items for insert to authenticated with check (app.has_any_role(array['admin','stores']));
create policy material_receipt_items_update on public.material_receipt_items for update to authenticated using (app.has_any_role(array['admin','stores'])) with check (app.has_any_role(array['admin','stores']));
create policy material_receipt_items_delete on public.material_receipt_items for delete to authenticated using (app.is_admin());

create policy pdi_records_select on public.pdi_records for select to authenticated using (app.is_staff());
create policy pdi_records_insert on public.pdi_records for insert to authenticated with check (app.has_any_role(array['admin','qa']));
create policy pdi_records_update on public.pdi_records for update to authenticated using (app.has_any_role(array['admin','qa'])) with check (app.has_any_role(array['admin','qa']));
create policy pdi_records_delete on public.pdi_records for delete to authenticated using (app.is_admin());

create policy pdi_items_select on public.pdi_items for select to authenticated using (app.is_staff());
create policy pdi_items_insert on public.pdi_items for insert to authenticated with check (app.has_any_role(array['admin','qa']));
create policy pdi_items_update on public.pdi_items for update to authenticated using (app.has_any_role(array['admin','qa'])) with check (app.has_any_role(array['admin','qa']));
create policy pdi_items_delete on public.pdi_items for delete to authenticated using (app.is_admin());

-- =============================================================================
-- DISPATCH
-- =============================================================================
create policy dispatches_select on public.dispatches for select to authenticated using (app.is_staff());
create policy dispatches_insert on public.dispatches for insert to authenticated with check (app.has_any_role(array['admin','logistics']));
create policy dispatches_update on public.dispatches for update to authenticated using (app.has_any_role(array['admin','logistics'])) with check (app.has_any_role(array['admin','logistics']));
create policy dispatches_delete on public.dispatches for delete to authenticated using (app.is_admin());

create policy dispatch_items_select on public.dispatch_items for select to authenticated using (app.is_staff());
create policy dispatch_items_insert on public.dispatch_items for insert to authenticated with check (app.has_any_role(array['admin','logistics']));
create policy dispatch_items_update on public.dispatch_items for update to authenticated using (app.has_any_role(array['admin','logistics'])) with check (app.has_any_role(array['admin','logistics']));
create policy dispatch_items_delete on public.dispatch_items for delete to authenticated using (app.is_admin());

create policy delivery_documents_select on public.delivery_documents for select to authenticated using (app.is_staff());
create policy delivery_documents_insert on public.delivery_documents for insert to authenticated with check (app.has_any_role(array['admin','logistics']));
create policy delivery_documents_update on public.delivery_documents for update to authenticated using (app.has_any_role(array['admin','logistics'])) with check (app.has_any_role(array['admin','logistics']));
create policy delivery_documents_delete on public.delivery_documents for delete to authenticated using (app.is_admin());

-- =============================================================================
-- FINANCE
-- =============================================================================
create policy invoices_select on public.invoices for select to authenticated using (app.is_staff());
create policy invoices_insert on public.invoices for insert to authenticated with check (app.has_any_role(array['admin','accounts']));
create policy invoices_update on public.invoices for update to authenticated using (app.has_any_role(array['admin','accounts'])) with check (app.has_any_role(array['admin','accounts']));
create policy invoices_delete on public.invoices for delete to authenticated using (app.is_admin());

create policy invoice_items_select on public.invoice_items for select to authenticated using (app.is_staff());
create policy invoice_items_insert on public.invoice_items for insert to authenticated with check (app.has_any_role(array['admin','accounts']));
create policy invoice_items_update on public.invoice_items for update to authenticated using (app.has_any_role(array['admin','accounts'])) with check (app.has_any_role(array['admin','accounts']));
create policy invoice_items_delete on public.invoice_items for delete to authenticated using (app.is_admin());

create policy payments_select on public.payments for select to authenticated using (app.is_staff());
create policy payments_insert on public.payments for insert to authenticated with check (app.has_any_role(array['admin','accounts']));
create policy payments_update on public.payments for update to authenticated using (app.has_any_role(array['admin','accounts'])) with check (app.has_any_role(array['admin','accounts']));
create policy payments_delete on public.payments for delete to authenticated using (app.is_admin());

create policy warranties_select on public.warranties for select to authenticated using (app.is_staff());
create policy warranties_insert on public.warranties for insert to authenticated with check (app.has_any_role(array['admin','accounts','qa','sales']));
create policy warranties_update on public.warranties for update to authenticated using (app.has_any_role(array['admin','accounts','qa','sales'])) with check (app.has_any_role(array['admin','accounts','qa','sales']));
create policy warranties_delete on public.warranties for delete to authenticated using (app.is_admin());

-- =============================================================================
-- OPS
-- =============================================================================
create policy tasks_select on public.tasks for select to authenticated using (app.is_staff());
create policy tasks_insert on public.tasks for insert to authenticated with check (app.is_staff());
create policy tasks_update on public.tasks for update to authenticated
  using (assigned_to = app.current_user_id() or app.has_any_role(array['admin','management']))
  with check (assigned_to = app.current_user_id() or app.has_any_role(array['admin','management']));
create policy tasks_delete on public.tasks for delete to authenticated using (app.is_admin());

create policy notifications_select on public.notifications for select to authenticated
  using (user_id = app.current_user_id() or app.has_any_role(array['admin','management']));
create policy notifications_insert on public.notifications for insert to authenticated
  with check (app.has_any_role(array['admin','management']));
create policy notifications_update on public.notifications for update to authenticated
  using (user_id = app.current_user_id() or app.has_any_role(array['admin','management']))
  with check (user_id = app.current_user_id() or app.has_any_role(array['admin','management']));
create policy notifications_delete on public.notifications for delete to authenticated using (app.is_admin());

-- audit_logs: readable by admin/management/accounts, append-only (no write policies).
create policy audit_logs_select on public.audit_logs for select to authenticated
  using (app.has_any_role(array['admin','management','accounts']));
