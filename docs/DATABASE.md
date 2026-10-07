# DATABASE.md — Ramprasad Defence: Data Dictionary

**Source of truth:** the versioned SQL in `../supabase/migrations/`. This document explains
each table, its purpose, key columns, status values and relationships. If this document and
the SQL disagree, the SQL wins — then fix this document.

**Validated:** all migrations execute and the security/trigger behaviour passes 32 automated
checks (see `../../REPORT.md`). Executed against PostgreSQL via PGlite (WASM Postgres) because
no live Supabase project is connected on this machine. **Not yet applied to a real Supabase
project** — that requires the project URL and keys.

---

## 1. Conventions

- **Primary keys:** every table has `id uuid primary key default gen_random_uuid()`.
- **Foreign keys:** enforced on every relationship; the referenced row cannot be deleted while
  children exist (or children cascade, as noted).
- **Timestamps:** `created_at`, `updated_at` (`timestamptz`, UTC). `updated_at` is maintained
  by trigger `app.set_updated_at()`.
- **Audit columns:** `created_by`, `updated_by` default to the signed-in user
  (`app.current_user_id()`).
- **Money:** `numeric(14,2)` — exact decimal, never floating point.
- **Quantities:** `numeric(14,3)`.
- **Status columns:** `text` with a `CHECK` constraint listing the allowed values (each table's
  values are listed below). To change a status list later, edit the `CHECK` in a new migration.
- **No duplicate derived data:** every line's `line_total` is a `GENERATED` column, so it can
  never disagree with its own quantity/price/discount/tax. Header totals are recalculated by
  trigger from the lines.
- **Soft delete:** `deleted_at` is not used in this version; deletes are admin-only and audited.

---

## 2. Table list (50 tables)

### 2.1 Identity & access (3)
### 2.2 Masters (8)
### 2.3 Documents (1)
### 2.4 Tender / opportunity (7)
### 2.5 Quotation (3)
### 2.6 Orders & procurement (14)
### 2.7 Receipts & inspection (4)
### 2.8 Dispatch, finance, warranty (7)
### 2.9 Operations (3)

**Added beyond the requested list, for normalisation (6):** `user_roles` (needed to attach
roles to users), `tender_notes` (Tender Management module), `invoice_items`,
`purchase_request_items`, `material_receipt_items`, `dispatch_items` (a header without lines
cannot be reconciled).

---

## 3. Identity and access

### users
- **Purpose:** application users (staff). One row per person.
- **Key columns:** `id` (our id, used by every audit column), `auth_user_id` (Supabase
  `auth.users.id`), `full_name`, `email` (unique, lower-case enforced), `phone`, `designation`,
  `department`, `is_active`, `mfa_enabled`, `last_login_at`.
- **Relationships:** referenced by every `created_by` / `updated_by` / actor column.
- **RLS:** a user may read their own row; `admin`/`management` may read all; only `admin` writes.

### roles
- **Purpose:** role catalogue. `code` is the key used everywhere.
- **Key columns:** `code` (PK), `name`, `description`, `is_system`.
- **Seeded values:** `admin`, `management`, `sales`, `technical`, `procurement`, `stores`,
  `qa`, `logistics`, `accounts`, `viewer`.
- **RLS:** all staff read; only `admin` writes.

### user_roles
- **Purpose:** many-to-many grants of roles to users.
- **Key columns:** `user_id` → users, `role_code` → roles, `granted_by`, `expires_at`.
  Unique on `(user_id, role_code)`.
- **RLS:** a user reads their own grants; `admin`/`management` read all; only `admin` writes.

### user_directory (view, not a table)
- **Purpose:** names-only directory (`id`, `full_name`, `designation`) of active users, so the
  "Assign employee" dropdown works for every staff member without exposing full user rows.
- **Access:** read-only to authenticated staff; the strict RLS on `users` is unchanged.

---

## 4. Masters

### customers
- **Purpose:** defence buyers (MoD, DPSUs, armed forces, paramilitary, …).
- **Key columns:** `code` (unique), `name`, `customer_type`, address fields, `gstin`, `pan`,
  `email`, `phone`, `status`.
- **Status:** `active` | `inactive` | `blacklisted`.
- **`customer_type`:** `mod`, `dpsu`, `armed_forces`, `paramilitary`, `ordnance_factory`,
  `police`, `government_other`, `private`, `other`.
- **RLS write roles:** admin, sales, procurement.

### customer_contacts
- **Purpose:** people at a customer. **`customer_id`** → customers (cascade).
- **Key columns:** `name`, `designation`, `email`, `phone`, `is_primary`.
- **Note:** a partial unique index allows at most one primary contact per customer.

### products
- **Purpose:** item master — the single reference for every line item in the chain.
- **Key columns:** `code` (unique), `name`, `category`, `unit`, `hsn_code`, `manufacturer`,
  `part_number`, `is_serialized`, `status` (`active`|`inactive`|`obsolete`).

### product_specifications
- **Purpose:** key/value technical specs per product (normalised, comparable).
- **Key columns:** `product_id` → products (cascade), `spec_key`, `spec_value`, `unit`,
  `sort_order`. Unique on `(product_id, spec_key)`.

### oems
- **Purpose:** OEM / supplier master.
- **Key columns:** `code` (unique), `name`, `oem_type`, address fields, `gstin`, `pan`,
  `payment_terms`, `status` (`active`|`inactive`|`blacklisted`).
- **RLS write roles:** admin, procurement.

### oem_contacts
- **Purpose:** people at an OEM. **`oem_id`** → oems (cascade). At most one primary.

### oem_products
- **Purpose:** approved product-to-OEM mapping with OEM part number, lead time, MOQ.
- **Key columns:** `oem_id`, `product_id`, `oem_part_number`, `lead_time_days`, `moq`,
  `currency`, `status`. Unique on `(oem_id, product_id)`.

### oem_price_history
- **Purpose:** price points per OEM/product over time (the "last cost" that used to be lost).
- **Key columns:** `oem_id`, `product_id`, `oem_product_id`, `unit_price`, `currency`,
  `valid_from`, `valid_to`, `source` (`quote`|`purchase_order`|`invoice`|`verbal`|`other`),
  `reference`.

---

## 5. Documents

### documents
- **Purpose:** central file register. Bytes live in Supabase Storage; this holds metadata and
  the **classification** that drives access.
- **Key columns:** `file_name`, `storage_bucket`, `storage_path` (unique per bucket),
  `mime_type`, `size_bytes`, `classification`, `entity_table` + `entity_id` (generic link),
  `version`, `checksum`, `uploaded_by`.
- **`classification`:** `unclassified` | `internal` | `confidential` | `controlled` | `itar_ear`.
  `controlled`/`itar_ear` are readable only by admin, management, technical, qa.
- **Linked from:** `tender_documents`, `delivery_documents`, `dispatches.pod_document_id`.

---

## 6. Tender / opportunity

### tenders
- **Purpose:** a received defence tender/enquiry. Root of the sales chain.
- **Key columns:** `tender_no` (unique), `customer_id`, `title`, `source`, `category`,
  `received_date`, `bid_due_date`, `corrigendum_date`, `emd_amount`, `emd_exempt`,
  `bid_validity_date`, `currency`, `estimated_value`, `priority`, `status`, `owner_user_id`.
- **Status:** `new` | `under_review` | `qualified` | `requirement_analysis` | `oem_pricing` |
  `quotation_preparation` | `approval_pending` | `submitted` | `technical_evaluation` |
  `commercial_evaluation` | `won` | `lost` | `cancelled` (the 13-stage tender pipeline,
  set by migration `0014_tender_workflow.sql`).
- **Priority:** `low` | `medium` | `high` | `critical`.
- **Rules:** `bid_due_date >= received_date`; `emd_amount >= 0`.

### tender_documents
- **Purpose:** link a stored document to a tender.
- **Key columns:** `tender_id` → tenders (cascade), `document_id` → documents (cascade),
  `doc_type` (`tender_document`|`corrigendum`|`technical_spec`|`drawing`|`emd_proof`|`other`).
  Unique on `(tender_id, document_id)`.

### tender_requirements
- **Purpose:** technical requirement lines of a tender.
- **Key columns:** `tender_id`, `line_no`, `product_id`, `description`, `specification`,
  `quantity`, `unit`, `feasibility`, `compliance_status`, `assigned_to`. Unique on
  `(tender_id, line_no)`; `quantity > 0`.
- **`feasibility`:** `feasible` | `clarification_needed` | `not_feasible`.
- **`compliance_status`:** `pending` | `compliant` | `partially_compliant` | `non_compliant` |
  `not_applicable`.

### opportunities
- **Purpose:** pre-tender sales opportunity (may or may not become a tender).
- **Key columns:** `customer_id`, `title`, `estimated_value`, `currency`, `probability`,
  `expected_close_date`, `stage`, `owner_user_id`.
- **Stage:** `new` | `qualified` | `proposal` | `negotiation` | `won` | `lost` | `on_hold`.

### requirements
- **Purpose:** general requirement items tied to an opportunity and/or a tender.
- **Key columns:** `opportunity_id`, `tender_id` (at least one required), `description`,
  `requirement_type`, `priority`, `status`, `owner_user_id`, `due_date`.
- **Status:** `open` | `in_progress` | `met` | `not_met` | `deferred`.

### compliance_items
- **Purpose:** compliance / eligibility checklist for a tender or opportunity.
- **Key columns:** `tender_id`, `opportunity_id` (at least one), `requirement`,
  `reference_clause`, `is_mandatory`, `compliance_status`, `evidence`, `verified_by`,
  `verified_at`.

### tender_notes
- **Purpose:** free-text notes recorded against a tender (Tender Management module). Newest
  first, each with author and timestamp.
- **Key columns:** `tender_id` → tenders (cascade), `note` (blank rejected), `created_by`,
  `created_at`.
- **RLS:** all staff read; admin/sales/technical may add.

---

## 7. Quotation

### quotations
- **Purpose:** a versioned quotation to a customer. A revision is a new row; an approved
  version is never overwritten (migration `0015_quotation_module.sql`).
- **Key columns:** `quotation_no` + `version` (unique together), `customer_id`, `tender_id`,
  `opportunity_id`, `quote_date`, `validity_date`, `currency`, `subtotal`, `tax_total`,
  `grand_total`, `margin_pct`, `status`, `submitted_at`.
- **Commercial terms (0015):** `payment_terms`, `delivery_terms`, `warranty`, `notes`.
- **Cost/margin totals (0015, trigger-maintained):** `total_purchase_cost`,
  `total_logistics_cost`, `total_other_cost`, `total_margin`.
- **Revision link (0015):** `revision_of` → another quotation; `approved_by`, `approved_at`.
- **Status:** `draft` | `pending_approval` | `approved` | `rejected` | `submitted` | `revised` |
  `won` | `lost` | `expired`.
- **Rules:** totals recalculated by `app.recalc_quotation_totals()` from `quotation_items`; a
  quotation in `approved`/`submitted`/`won`/`lost` is **frozen** — content edits are refused by
  trigger (`app.protect_approved_quotation`), and a revision is required. Status changes remain
  allowed. At most one `approved` approval step per quotation (unique index).

### quotation_items
- **Purpose:** line items of a quotation, with cost, margin and compliance.
- **Key columns:** `quotation_id` (cascade), `line_no`, `product_id`,
  `tender_requirement_id`, `source_oem_id` (OEM), `description`, `quantity`, `unit`,
  `unit_price` (selling per unit), `discount_pct`, `tax_pct`, `line_total` (**generated**).
- **Costs (0015):** `purchase_unit_cost`, `logistics_unit_cost`, `other_unit_cost`.
- **Compliance (0015):** `technical_compliance` (`pending` | `compliant` |
  `partially_compliant` | `non_compliant` | `not_applicable`).
- **Generated columns (0015):**
  - `line_total` = `round(qty*unit_price*(1-discount/100)*(1+tax/100), 2)`
  - `line_base` = `round(qty*unit_price*(1-discount/100), 2)` (net selling)
  - `line_cost` = `round(qty*(purchase+logistics+other), 2)`
  - `line_margin` = `line_base - line_cost`
  - `line_margin_pct` = margin as a percentage of net selling
- **Rules:** lines of a frozen quotation cannot be inserted, changed or deleted
  (`app.protect_approved_quotation_items`).

### quotation_approvals
- **Purpose:** approval trail for a quotation (one or more steps).
- **Key columns:** `quotation_id` (cascade), `step_no`, `approver_user_id`, `decision`,
  `comments`, `decided_at`. Unique on `(quotation_id, step_no)`.
- **Decision:** `pending` | `approved` | `rejected` | `returned`.
- **RLS write roles:** admin, management only.

---

## 8. Orders and procurement

### customer_orders
- **Purpose:** a purchase order received from the customer.
- **Key columns:** `order_no` + `customer_id` (unique together), `order_date`, `quotation_id`,
  `currency`, `subtotal`, `tax_total`, `grand_total`, delivery/payment terms, consignee,
  `status`.
- **Status:** `received` | `confirmed` | `in_procurement` | `partially_delivered` |
  `delivered` | `invoiced` | `closed` | `cancelled`.
- **Totals:** recalculated by trigger from `order_items`.

### order_items
- **Purpose:** line items of a customer order.
- **Key columns:** `customer_order_id` (cascade), `line_no`, `product_id`,
  `quotation_item_id`, `description`, `quantity`, `unit`, `unit_price`, `discount_pct`,
  `tax_pct`, `line_total` (generated), `delivered_qty`, `status`.
- **`delivered_qty`** is kept true to `dispatch_items` by trigger.
- **Status:** `open` | `partially_delivered` | `delivered` | `cancelled`.

### purchase_requests
- **Purpose:** internal request to procure, approved then converted into POs.
- **Key columns:** `request_no` (unique), `customer_order_id`, `requested_by`, `needed_by`,
  `priority`, `status`, `approved_by`, `approved_at`.
- **Status:** `draft` | `submitted` | `approved` | `rejected` | `converted` | `cancelled`.

### purchase_request_items
- **Purpose:** lines of a purchase request. `purchase_request_id` (cascade), `line_no`,
  `product_id`, `description`, `quantity`, `unit`, `required_by`, `status`
  (`open`|`converted`|`cancelled`).

### purchase_orders
- **Purpose:** a PO issued to an OEM.
- **Key columns:** `po_no` (unique), `po_date`, `oem_id`, `customer_order_id`,
  `purchase_request_id`, `currency`, `subtotal`, `tax_total`, `grand_total`,
  `expected_delivery_date`, `terms`, `status`, `approved_by`.
- **Status:** `draft` | `pending_approval` | `approved` | `sent` | `partially_received` |
  `received` | `cancelled` | `closed`.
- **Totals:** recalculated by trigger from `purchase_order_items`.

### purchase_order_items
- **Purpose:** lines of a PO to an OEM.
- **Key columns:** `purchase_order_id` (cascade), `line_no`, `product_id`, `order_item_id`
  (links the PO line to the customer order line), `description`, `quantity`, `unit`,
  `unit_price`, `discount_pct`, `tax_pct`, `line_total` (generated), `received_qty`, `status`.
- **`received_qty`** is kept true to `material_receipt_items` by trigger.
- **Status:** `open` | `partially_received` | `received` | `cancelled`.

### material_requirements (0016)
- **Purpose:** the demand to procure for a customer order — first step of procurement.
- **Key columns:** `requirement_no` (unique), `customer_order_id`, `requested_by`,
  `required_by_date` (drives delivery-risk), `priority`, `status`, `notes`.
- **Status:** `open` | `sourcing` | `rfq_sent` | `quoted` | `ordered` |
  `partially_received` | `received` | `cancelled`.

### material_requirement_items (0016)
- **Purpose:** lines of a material requirement. `material_requirement_id` (cascade), `line_no`,
  `product_id`, `order_item_id`, `description`, `quantity` (>0), `unit`, `required_by`, `status`.

### oem_rfqs (0016)
- **Purpose:** a request for quotation sent to one OEM. Several rows share an `rfq_no`.
- **Key columns:** `rfq_no` + `oem_id` (unique together), `material_requirement_id`,
  `purchase_request_id`, `sent_date`, `due_date`, `currency`, `status`.
- **Status:** `draft` | `sent` | `quotes_received` | `closed` | `cancelled`.

### oem_rfq_items (0016)
- **Purpose:** lines asked of the OEM. `oem_rfq_id` (cascade), `line_no`, `product_id`,
  `material_requirement_item_id`, `description`, `quantity`, `unit`.

### oem_quotations (0016)
- **Purpose:** a priced quotation received from an OEM. Selecting one creates the PO.
- **Key columns:** `quotation_no` (unique), `oem_id`, `oem_rfq_id`, `quote_date`,
  `validity_date`, `currency`, `payment_terms`, `delivery_terms`, `warranty`,
  `lead_time_days`, `subtotal`, `tax_total`, `grand_total`, `status`, `selected_at`.
- **Status:** `received` | `selected` | `rejected` | `expired`.
- **Totals:** recalculated by trigger from `oem_quotation_items`.

### oem_quotation_items (0016)
- **Purpose:** lines of an OEM quotation. `oem_quotation_id` (cascade), `line_no`,
  `oem_rfq_item_id`, `product_id`, `description`, `quantity`, `unit`, `unit_price`
  (purchase price), `discount_pct`, `tax_pct`, `line_total` (generated).

### purchase_approvals (0016)
- **Purpose:** approval trail for a purchase order. `purchase_order_id` (cascade), `step_no`,
  `approver_user_id`, `decision` (`pending`|`approved`|`rejected`|`returned`), `comments`,
  `decided_at`. At most one `approved` step per PO (unique index).

### procurement_documents (0016)
- **Purpose:** links a stored document to a procurement entity as a compliance/quality
  document, with an optional expiry.
- **Key columns:** `entity_type` (`oem`|`oem_quotation`|`purchase_order`|`material_receipt`),
  `entity_id`, `document_id`, `doc_type`, `expires_on`. Unique on
  `(entity_type, entity_id, document_id)`.

### Links added to existing tables (0016)
- `purchase_requests.material_requirement_id`.
- `purchase_orders.oem_quotation_id`, `material_requirement_id`, `payment_terms`, `warranty`,
  `actual_delivery_date` (trigger-maintained from receipts).

---

## 9. Receipts and inspection

### material_receipts
- **Purpose:** goods receipt note (GRN) against a PO, whole or partial.
- **Key columns:** `grn_no` (unique), `purchase_order_id`, `oem_id`, `docket_no`,
  `dispatch_date`, `expected_date`, `received_date`, `received_by`, `status`,
  `inspection_status`.
- **Status:** `pending` | `partial` | `received` | `rejected`.
- **`inspection_status`:** `pending` | `in_progress` | `passed` | `failed` | `partial`.
- **Segregation:** `received_by` may not equal the related PO's `created_by` (trigger).

### material_receipt_items
- **Purpose:** received quantities per PO line, split accepted/rejected.
- **Key columns:** `material_receipt_id` (cascade), `purchase_order_item_id` (restrict),
  `product_id`, `qty_received`, `qty_accepted`, `qty_rejected`.
- **Rule:** `qty_accepted + qty_rejected <= qty_received`.

### pdi_records
- **Purpose:** inspection / pre-delivery inspection record.
- **Key columns:** `pdi_no` (unique), `material_receipt_id`, `customer_order_id`,
  `inspection_type`, `inspection_date`, `inspector_user_id`, `agency`, `result`,
  `certificate_no`, `certificate_date`.
- **`inspection_type`:** `incoming` | `in_process` | `final` | `pdi` | `third_party` | `dgqa` |
  `dgaqa`.
- **`result`:** `pending` | `pass` | `fail` | `conditional`.
- **Gate:** a dispatch line is refused unless a `pass` PDI exists for its order line (trigger).

### pdi_items
- **Purpose:** inspection result per received line.
- **Key columns:** `pdi_record_id` (cascade), `material_receipt_item_id`, `product_id`,
  `qty_inspected`, `qty_passed`, `qty_failed`, `defect_code`, `defect_notes`.
- **Rule:** `qty_passed + qty_failed <= qty_inspected`.

---

## 10. Dispatch, finance, warranty

### dispatches
- **Purpose:** a shipment to the customer (may be partial).
- **Key columns:** `dispatch_no` (unique), `customer_order_id`, `customer_id`,
  `dispatch_date`, `carrier`, `tracking_no`, `eway_bill_no`, consignee, `status`,
  `delivery_confirmed_date`, `pod_document_id` → documents.
- **Status:** `prepared` | `dispatched` | `in_transit` | `delivered` | `returned` | `cancelled`.

### dispatch_items
- **Purpose:** lines of a dispatch.
- **Key columns:** `dispatch_id` (cascade), `order_item_id` (restrict), `product_id`,
  `quantity`, `packing_details`.
- **Gate:** insert is refused unless a passed PDI exists for `order_item_id` (trigger).

### delivery_documents
- **Purpose:** documents attached to a dispatch.
- **Key columns:** `dispatch_id` (cascade), `document_id` (cascade), `doc_type`
  (`packing_list`|`eway_bill`|`pod`|`lr`|`insurance`|`invoice_copy`|`other`).

### invoices
- **Purpose:** customer invoice.
- **Key columns:** `invoice_no` (unique), `invoice_date`, `customer_id`, `customer_order_id`,
  `dispatch_id`, `currency`, `subtotal`, `tax_total`, `grand_total`, `due_date`, `status`.
- **Status:** `draft` | `issued` | `partially_paid` | `paid` | `overdue` | `cancelled` | `void`.
- **Rules:** totals recalculated from `invoice_items`; once `paid`/`void` the financial fields
  are locked (trigger); `partially_paid`/`paid` are derived from recorded payments (trigger).

### invoice_items
- **Purpose:** lines of an invoice (so the invoice reconciles to its lines).
- **Key columns:** `invoice_id` (cascade), `line_no`, `product_id`, `order_item_id`,
  `description`, `quantity`, `unit`, `unit_price`, `discount_pct`, `tax_pct`,
  `line_total` (generated).

### payments
- **Purpose:** both customer receipts and OEM payments in one table.
- **Key columns:** `payment_no` (unique), `payment_type`, `invoice_id`, `purchase_order_id`,
  `customer_id`, `oem_id`, `payment_date`, `amount`, `currency`, `mode`, `reference`,
  `recorded_by`.
- **`payment_type`:** `customer_receipt` | `oem_payment`.
- **`mode`:** `neft` | `rtgs` | `upi` | `cheque` | `cash` | `card` | `other`.
- **Rules:** `amount > 0`; a `customer_receipt` must reference an invoice; an `oem_payment`
  must reference a purchase order. **Segregation:** the invoice creator may not record its
  payment (trigger).

### warranties
- **Purpose:** warranty / guarantee coverage per order item, product or customer.
- **Key columns:** `customer_id`, `customer_order_id`, `order_item_id`, `product_id`,
  `warranty_type`, `start_date`, `end_date`, `terms`, `status`, `claim_notes`.
- **Status:** `active` | `expired` | `void` | `claimed`.

---

## 11. Operations

### tasks
- **Purpose:** follow-ups / to-dos, optionally linked to any record.
- **Key columns:** `title`, `description`, `entity_table` + `entity_id`, `assigned_to`,
  `due_date`, `priority`, `status`, `completed_at`.
- **Status:** `open` | `in_progress` | `blocked` | `done` | `cancelled`.

### notifications
- **Purpose:** in-app / email notifications per user.
- **Key columns:** `user_id` (cascade), `title`, `body`, `entity_table` + `entity_id`,
  `channel` (`in_app`|`email`), `status` (`unread`|`read`|`archived`), `read_at`.
- **RLS:** a user reads and updates only their own notifications.

### audit_logs
- **Purpose:** append-only change history — who changed what, when.
- **Key columns:** `actor_user_id`, `action` (`insert`|`update`|`delete`|`approve`|`submit`|
  `receive`|`dispatch`|`login`|`export`|`other`), `entity_table`, `entity_id`, `before_data`
  (jsonb), `after_data` (jsonb), `ip_address`.
- **Written only by** trigger `app.audit_row()` (SECURITY DEFINER). No user can insert, update
  or delete audit rows; RLS filters every write to zero rows.
- **Read:** admin, management, accounts.

---

## 12. Triggers (behaviour that keeps data correct)

| Trigger | On | Does |
|---|---|---|
| `trg_touch_*` | every table with `updated_at` | sets `updated_at = now()` on update |
| `trg_audit_*` | every business table | writes an `audit_logs` row per change |
| `trg_totals_quotation` | `quotation_items` | recalculates quotation totals incl. cost and margin |
| `trg_protect_approved_quotation` | `quotations` | freezes content of an approved/submitted/won/lost quotation |
| `trg_protect_quotation_items` | `quotation_items` | freezes the lines of a frozen quotation |
| `trg_totals_customer_order` | `order_items` | recalculates customer order totals |
| `trg_totals_purchase_order` | `purchase_order_items` | recalculates PO totals |
| `trg_totals_invoice` | `invoice_items` | recalculates invoice totals |
| `trg_po_item_received` | `material_receipt_items` | keeps `received_qty` + PO status true |
| `trg_order_item_delivered` | `dispatch_items` | keeps `delivered_qty` + order status true |
| `trg_dispatch_requires_pdi` | `dispatch_items` | blocks dispatch without a passed PDI |
| `trg_segregation_payment` | `payments` | invoice creator ≠ payment recorder |
| `trg_segregation_receipt` | `material_receipts` | PO creator ≠ goods receiver |
| `trg_lock_paid_invoice` | `invoices` | locks financial fields when paid/void |
| `trg_invoice_status` | `payments` | derives invoice status from payments |
| `trg_totals_oem_quotation` | `oem_quotation_items` | recalculates OEM quotation totals |
| `trg_po_actual_delivery` | `material_receipts` | sets PO `actual_delivery_date` from receipts |

---

## 13. How to apply

On a machine with the Supabase CLI and Docker:

```
cd "Ramprasad-Defence Project"
supabase init           # once, creates supabase/config.toml
supabase link --project-ref <your-project-ref>
supabase db push        # applies supabase/migrations in order
supabase db reset       # local: rebuild and apply migrations + seed
```

Migrations must be applied in filename order; the numbering (0001…0013) enforces this.

## 14. Known limits / decisions to revisit

- **Status values are `CHECK` constraints, not a lookup table.** Changing them is a migration.
  Acceptable for MVP; move to a `status_definitions` table if the business renames statuses often.
- **`oem_price_history` is append-style**, not enforced append-only; rows can be edited by
  admin. Treat as history.
- **No stock/inventory ledger** in this version (receipts and dispatches are recorded, but
  there is no bin-level stock table). Deliberate MVP boundary.
- **No multi-company/tenant column.** Single company assumed (PRD A1).
- **Data residency** is a deployment decision (PRD §10 Q1) and does not change this schema.
