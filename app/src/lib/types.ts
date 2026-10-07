/** Minimal row shapes used by the module. Kept small on purpose. */

export interface Tender {
  id: string;
  tender_no: string;
  customer_id: string;
  title: string;
  description: string | null;
  source: string | null;
  category: string | null;
  received_date: string;
  bid_due_date: string | null;
  emd_amount: number | null;
  currency: string;
  priority: 'low' | 'medium' | 'high' | 'critical';
  status: string;
  owner_user_id: string | null;
  notes: string | null;
  created_at: string;
  updated_at: string;
}

export interface Customer {
  id: string;
  name: string;
}

export interface UserDirectoryEntry {
  id: string;
  full_name: string;
  designation: string | null;
}

export interface TenderRequirement {
  id: string;
  tender_id: string;
  line_no: number;
  description: string;
  specification: string | null;
  quantity: number;
  unit: string;
  feasibility: string;
  compliance_status: string;
  created_at: string;
}

export interface TenderNote {
  id: string;
  tender_id: string;
  note: string;
  created_by: string | null;
  created_at: string;
}

export interface TenderTask {
  id: string;
  title: string;
  assigned_to: string | null;
  due_date: string | null;
  priority: string;
  status: string;
  created_at: string;
}

export interface TenderDocument {
  id: string;
  file_name: string;
  storage_path: string;
  classification: string;
  doc_type: string;
  created_at: string;
}

export interface ActivityEntry {
  id: string;
  action: string;
  actor_user_id: string | null;
  created_at: string;
  entity_table: string;
}

export interface Quotation {
  id: string;
  quotation_no: string;
  version: number;
  customer_id: string;
  tender_id: string | null;
  opportunity_id: string | null;
  quote_date: string;
  validity_date: string | null;
  currency: string;
  subtotal: number;
  tax_total: number;
  grand_total: number;
  margin_pct: number | null;
  status: string;
  submitted_at: string | null;
  notes: string | null;
  payment_terms: string | null;
  delivery_terms: string | null;
  warranty: string | null;
  revision_of: string | null;
  approved_by: string | null;
  approved_at: string | null;
  total_purchase_cost: number;
  total_logistics_cost: number;
  total_other_cost: number;
  total_margin: number;
  created_at: string;
  updated_at: string;
}

export interface QuotationListItem extends Quotation {
  customer_name: string;
  tender_no: string | null;
}

export interface QuotationItem {
  id: string;
  quotation_id: string;
  line_no: number;
  product_id: string | null;
  tender_requirement_id: string | null;
  source_oem_id: string | null;
  description: string;
  quantity: number;
  unit: string;
  unit_price: number;
  discount_pct: number;
  tax_pct: number;
  line_base: number;
  line_cost: number;
  line_margin: number;
  line_margin_pct: number | null;
  line_total: number;
  purchase_unit_cost: number;
  logistics_unit_cost: number;
  other_unit_cost: number;
  technical_compliance: string;
}

export interface QuotationApproval {
  id: string;
  quotation_id: string;
  step_no: number;
  approver_user_id: string | null;
  decision: string;
  comments: string | null;
  decided_at: string | null;
  created_at: string;
}

export interface Oem {
  id: string;
  name: string;
}

export interface MaterialRequirement {
  id: string;
  requirement_no: string;
  customer_order_id: string | null;
  requested_by: string | null;
  required_by_date: string | null;
  priority: string;
  status: string;
  notes: string | null;
  created_at: string;
}

export interface MaterialRequirementItem {
  id: string;
  material_requirement_id: string;
  line_no: number;
  product_id: string | null;
  order_item_id: string | null;
  description: string;
  quantity: number;
  unit: string;
  required_by: string | null;
  status: string;
}

export interface OemRfq {
  id: string;
  rfq_no: string;
  oem_id: string;
  material_requirement_id: string | null;
  purchase_request_id: string | null;
  sent_date: string | null;
  due_date: string | null;
  currency: string;
  status: string;
  created_at: string;
}

export interface OemRfqItem {
  id: string;
  oem_rfq_id: string;
  line_no: number;
  product_id: string | null;
  description: string;
  quantity: number;
  unit: string;
}

export interface OemQuotation {
  id: string;
  quotation_no: string;
  oem_id: string;
  oem_rfq_id: string | null;
  quote_date: string;
  validity_date: string | null;
  currency: string;
  payment_terms: string | null;
  delivery_terms: string | null;
  warranty: string | null;
  lead_time_days: number | null;
  subtotal: number;
  tax_total: number;
  grand_total: number;
  status: string;
  selected_at: string | null;
  notes: string | null;
}

export interface OemQuotationItem {
  id: string;
  oem_quotation_id: string;
  line_no: number;
  product_id: string | null;
  description: string;
  quantity: number;
  unit: string;
  unit_price: number;
  tax_pct: number;
  line_total: number;
}

export interface PurchaseApproval {
  id: string;
  purchase_order_id: string;
  step_no: number;
  approver_user_id: string | null;
  decision: string;
  comments: string | null;
  decided_at: string | null;
  created_at: string;
}

export interface ProcurementDocument {
  id: string;
  entity_type: string;
  entity_id: string;
  document_id: string;
  doc_type: string;
  expires_on: string | null;
  file_name?: string;
}

export interface PurchaseOrder {
  id: string;
  po_no: string;
  po_date: string;
  oem_id: string;
  customer_order_id: string | null;
  purchase_request_id: string | null;
  oem_quotation_id: string | null;
  material_requirement_id: string | null;
  currency: string;
  subtotal: number;
  tax_total: number;
  grand_total: number;
  expected_delivery_date: string | null;
  actual_delivery_date: string | null;
  payment_terms: string | null;
  warranty: string | null;
  status: string;
  approved_by: string | null;
  approved_at: string | null;
  created_at: string;
}

export interface PurchaseOrderItem {
  id: string;
  purchase_order_id: string;
  line_no: number;
  product_id: string | null;
  order_item_id: string | null;
  description: string;
  quantity: number;
  unit: string;
  unit_price: number;
  tax_pct: number;
  line_total: number;
  received_qty: number;
  status: string;
}

export interface MaterialReceipt {
  id: string;
  grn_no: string;
  purchase_order_id: string;
  oem_id: string;
  docket_no: string | null;
  received_date: string | null;
  status: string;
  inspection_status: string;
  created_at: string;
}

export interface PurchaseRequestRef {
  id: string;
  request_no: string;
  material_requirement_id: string | null;
  customer_order_id: string | null;
  needed_by: string | null;
  status: string;
}
