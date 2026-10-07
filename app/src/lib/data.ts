import { createClient } from './supabase/server';
import { deadlineIndicator } from './deadline';
import type {
  ActivityEntry,
  Customer,
  MaterialReceipt,
  MaterialRequirement,
  MaterialRequirementItem,
  Oem,
  OemQuotation,
  OemQuotationItem,
  OemRfq,
  OemRfqItem,
  ProcurementDocument,
  PurchaseApproval,
  PurchaseOrder,
  PurchaseOrderItem,
  PurchaseRequestRef,
  Quotation,
  QuotationApproval,
  QuotationItem,
  QuotationListItem,
  Tender,
  TenderDocument,
  TenderNote,
  TenderRequirement,
  TenderTask,
  UserDirectoryEntry,
} from './types';

export interface TenderListFilters {
  q?: string;
  status?: string;
  priority?: string;
  owner?: string;
  deadline?: string; // 'red' | 'yellow' | 'green'
}

export interface TenderListRow extends Tender {
  customer_name: string;
  owner_name: string;
}

/** Tenders for the list page, filtered, with the deadline indicator attached. */
export async function listTenders(filters: TenderListFilters): Promise<TenderListRow[]> {
  const supabase = createClient();
  let query = supabase
    .from('tenders')
    .select('*, customer:customers(id,name)')
    .order('bid_due_date', { ascending: true, nullsFirst: false })
    .limit(300);

  if (filters.q) {
    const term = filters.q.replace(/[%,]/g, ' ');
    query = query.or(`tender_no.ilike.%${term}%,title.ilike.%${term}%`);
  }
  if (filters.status) query = query.eq('status', filters.status);
  if (filters.priority) query = query.eq('priority', filters.priority);
  if (filters.owner) query = query.eq('owner_user_id', filters.owner);

  const { data, error } = await query;
  if (error) throw new Error(`Could not load tenders: ${error.message}`);

  const directory = await getUserDirectory();
  const ownerNames = new Map(directory.map((u) => [u.id, u.full_name]));

  const rows: TenderListRow[] = (data ?? []).map((t: any) => ({
    ...t,
    customer_name: t.customer?.name ?? '—',
    owner_name: t.owner_user_id ? ownerNames.get(t.owner_user_id) ?? '—' : 'Unassigned',
  }));

  const filtered = filters.deadline
    ? rows.filter(
        (r) => deadlineIndicator(r.bid_due_date, r.priority).color === filters.deadline,
      )
    : rows;

  return filtered;
}

export async function getTender(id: string): Promise<(Tender & { customer_name: string }) | null> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from('tenders')
    .select('*, customer:customers(id,name)')
    .eq('id', id)
    .maybeSingle();
  if (error) throw new Error(`Could not load tender: ${error.message}`);
  if (!data) return null;
  return { ...(data as any), customer_name: (data as any).customer?.name ?? '—' };
}

export async function listCustomers(): Promise<Customer[]> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from('customers')
    .select('id,name')
    .eq('status', 'active')
    .order('name');
  if (error) throw new Error(`Could not load customers: ${error.message}`);
  return (data ?? []) as Customer[];
}

export async function getUserDirectory(): Promise<UserDirectoryEntry[]> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from('user_directory')
    .select('id,full_name,designation')
    .order('full_name');
  if (error) throw new Error(`Could not load users: ${error.message}`);
  return (data ?? []) as UserDirectoryEntry[];
}

export async function getRequirements(tenderId: string): Promise<TenderRequirement[]> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from('tender_requirements')
    .select('*')
    .eq('tender_id', tenderId)
    .order('line_no');
  if (error) throw new Error(`Could not load requirements: ${error.message}`);
  return (data ?? []) as TenderRequirement[];
}

export async function getNotes(tenderId: string): Promise<TenderNote[]> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from('tender_notes')
    .select('*')
    .eq('tender_id', tenderId)
    .order('created_at', { ascending: false });
  if (error) throw new Error(`Could not load notes: ${error.message}`);
  return (data ?? []) as TenderNote[];
}

export async function getTasks(tenderId: string): Promise<TenderTask[]> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from('tasks')
    .select('*')
    .eq('entity_table', 'tenders')
    .eq('entity_id', tenderId)
    .order('status')
    .order('due_date', { ascending: true, nullsFirst: false });
  if (error) throw new Error(`Could not load tasks: ${error.message}`);
  return (data ?? []) as TenderTask[];
}

export async function getDocuments(tenderId: string): Promise<TenderDocument[]> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from('tender_documents')
    .select('doc_type, documents(id,file_name,storage_path,classification,created_at)')
    .eq('tender_id', tenderId);
  if (error) throw new Error(`Could not load documents: ${error.message}`);
  return (data ?? []).map((row: any) => ({
    id: row.documents.id,
    file_name: row.documents.file_name,
    storage_path: row.documents.storage_path,
    classification: row.documents.classification,
    doc_type: row.doc_type,
    created_at: row.documents.created_at,
  }));
}

export async function getActivity(tenderId: string): Promise<ActivityEntry[]> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from('audit_logs')
    .select('id,action,actor_user_id,created_at,entity_table')
    .eq('entity_table', 'tenders')
    .eq('entity_id', tenderId)
    .order('created_at', { ascending: false })
    .limit(50);
  if (error) throw new Error(`Could not load activity: ${error.message}`);
  return (data ?? []) as ActivityEntry[];
}

/** Short-lived signed URL for a private document. */
export async function getDocumentUrl(storagePath: string): Promise<string | null> {
  const supabase = createClient();
  const bucket = process.env.SUPABASE_DOCUMENTS_BUCKET || 'documents';
  const { data, error } = await supabase.storage.from(bucket).createSignedUrl(storagePath, 60 * 10);
  if (error) return null;
  return data?.signedUrl ?? null;
}

// ===========================================================================
// Quotations
// ===========================================================================

export interface QuotationListFilters {
  q?: string;
  status?: string;
  customer?: string;
}

export async function listQuotations(filters: QuotationListFilters): Promise<QuotationListItem[]> {
  const supabase = createClient();
  let query = supabase
    .from('quotations')
    .select('*, customer:customers(name), tender:tenders(tender_no)')
    .order('created_at', { ascending: false })
    .limit(300);

  if (filters.q) {
    const term = filters.q.replace(/[%,]/g, ' ');
    query = query.ilike('quotation_no', `%${term}%`);
  }
  if (filters.status) query = query.eq('status', filters.status);
  if (filters.customer) query = query.eq('customer_id', filters.customer);

  const { data, error } = await query;
  if (error) throw new Error(`Could not load quotations: ${error.message}`);

  return (data ?? []).map((row: any) => ({
    ...row,
    customer_name: row.customer?.name ?? '—',
    tender_no: row.tender?.tender_no ?? null,
  }));
}

export async function getQuotation(id: string): Promise<(Quotation & { customer_name: string; tender_no: string | null }) | null> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from('quotations')
    .select('*, customer:customers(name), tender:tenders(tender_no)')
    .eq('id', id)
    .maybeSingle();
  if (error) throw new Error(`Could not load quotation: ${error.message}`);
  if (!data) return null;
  return { ...(data as any), customer_name: (data as any).customer?.name ?? '—', tender_no: (data as any).tender?.tender_no ?? null };
}

export async function getQuotationItems(quotationId: string): Promise<QuotationItem[]> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from('quotation_items')
    .select('*')
    .eq('quotation_id', quotationId)
    .order('line_no');
  if (error) throw new Error(`Could not load quotation lines: ${error.message}`);
  return (data ?? []) as QuotationItem[];
}

export async function getQuotationApprovals(quotationId: string): Promise<QuotationApproval[]> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from('quotation_approvals')
    .select('*')
    .eq('quotation_id', quotationId)
    .order('step_no');
  if (error) throw new Error(`Could not load approvals: ${error.message}`);
  return (data ?? []) as QuotationApproval[];
}

export async function getQuotationRevisions(quotationNo: string): Promise<Quotation[]> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from('quotations')
    .select('*')
    .eq('quotation_no', quotationNo)
    .order('version');
  if (error) throw new Error(`Could not load revisions: ${error.message}`);
  return (data ?? []) as Quotation[];
}

export async function getQuotationTasks(quotationId: string): Promise<TenderTask[]> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from('tasks')
    .select('*')
    .eq('entity_table', 'quotations')
    .eq('entity_id', quotationId)
    .order('status')
    .order('due_date', { ascending: true, nullsFirst: false });
  if (error) throw new Error(`Could not load tasks: ${error.message}`);
  return (data ?? []) as TenderTask[];
}

export async function getQuotationActivity(quotationId: string): Promise<ActivityEntry[]> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from('audit_logs')
    .select('id,action,actor_user_id,created_at,entity_table')
    .eq('entity_table', 'quotations')
    .eq('entity_id', quotationId)
    .order('created_at', { ascending: false })
    .limit(50);
  if (error) throw new Error(`Could not load activity: ${error.message}`);
  return (data ?? []) as ActivityEntry[];
}

export async function listOems(): Promise<Oem[]> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from('oems')
    .select('id,name')
    .eq('status', 'active')
    .order('name');
  if (error) throw new Error(`Could not load OEMs: ${error.message}`);
  return (data ?? []) as Oem[];
}

export async function listProducts(): Promise<{ id: string; name: string; code: string }[]> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from('products')
    .select('id,name,code')
    .eq('status', 'active')
    .order('name');
  if (error) throw new Error(`Could not load products: ${error.message}`);
  return (data ?? []) as { id: string; name: string; code: string }[];
}

/** The signed-in user's own row and role codes, for showing approval controls. */
export async function getCurrentContext(): Promise<{ id: string; full_name: string; roles: string[] } | null> {
  const supabase = createClient();
  const { data: auth } = await supabase.auth.getUser();
  if (!auth.user) return null;

  const { data: me } = await supabase
    .from('users')
    .select('id, full_name')
    .eq('auth_user_id', auth.user.id)
    .maybeSingle();
  if (!me) return null;

  const { data: roles } = await supabase
    .from('user_roles')
    .select('role_code')
    .eq('user_id', me.id);

  return { id: me.id, full_name: me.full_name, roles: (roles ?? []).map((r: any) => r.role_code) };
}

/** Lightweight tender list for the "link to tender" dropdown. */
export async function listTenderOptions(): Promise<
  { id: string; tender_no: string; title: string; customer_id: string }[]
> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from('tenders')
    .select('id, tender_no, title, customer_id')
    .order('created_at', { ascending: false })
    .limit(300);
  if (error) throw new Error(`Could not load tenders: ${error.message}`);
  return (data ?? []) as { id: string; tender_no: string; title: string; customer_id: string }[];
}

// ===========================================================================
// Procurement
// ===========================================================================

export async function listMaterialRequirements(filters: { q?: string; status?: string } = {}): Promise<
  (MaterialRequirement & { customer_order_no: string | null })[]
> {
  const supabase = createClient();
  let query = supabase
    .from('material_requirements')
    .select('*, customer_order:customer_orders(order_no)')
    .order('required_by_date', { ascending: true, nullsFirst: false })
    .limit(300);
  if (filters.q) query = query.ilike('requirement_no', `%${filters.q.replace(/[%,]/g, ' ')}%`);
  if (filters.status) query = query.eq('status', filters.status);

  const { data, error } = await query;
  if (error) throw new Error(`Could not load material requirements: ${error.message}`);
  return (data ?? []).map((r: any) => ({ ...r, customer_order_no: r.customer_order?.order_no ?? null }));
}

export async function getMaterialRequirement(id: string): Promise<MaterialRequirement | null> {
  const supabase = createClient();
  const { data, error } = await supabase.from('material_requirements').select('*').eq('id', id).maybeSingle();
  if (error) throw new Error(`Could not load material requirement: ${error.message}`);
  return (data as MaterialRequirement) ?? null;
}

export async function getMaterialRequirementItems(id: string): Promise<MaterialRequirementItem[]> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from('material_requirement_items')
    .select('*')
    .eq('material_requirement_id', id)
    .order('line_no');
  if (error) throw new Error(`Could not load requirement items: ${error.message}`);
  return (data ?? []) as MaterialRequirementItem[];
}

export async function getOemRfqsForRequirement(requirementId: string): Promise<OemRfq[]> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from('oem_rfqs')
    .select('*')
    .eq('material_requirement_id', requirementId)
    .order('created_at');
  if (error) throw new Error(`Could not load RFQs: ${error.message}`);
  return (data ?? []) as OemRfq[];
}

export async function getOemRfq(id: string): Promise<(OemRfq & { oem_name: string }) | null> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from('oem_rfqs')
    .select('*, oem:oems(name)')
    .eq('id', id)
    .maybeSingle();
  if (error) throw new Error(`Could not load RFQ: ${error.message}`);
  if (!data) return null;
  return { ...(data as any), oem_name: (data as any).oem?.name ?? '—' };
}

export async function getOemRfqItems(id: string): Promise<OemRfqItem[]> {
  const supabase = createClient();
  const { data, error } = await supabase.from('oem_rfq_items').select('*').eq('oem_rfq_id', id).order('line_no');
  if (error) throw new Error(`Could not load RFQ items: ${error.message}`);
  return (data ?? []) as OemRfqItem[];
}

export async function getOemQuotationsForRfq(rfqId: string): Promise<OemQuotation[]> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from('oem_quotations')
    .select('*')
    .eq('oem_rfq_id', rfqId)
    .order('created_at');
  if (error) throw new Error(`Could not load OEM quotations: ${error.message}`);
  return (data ?? []) as OemQuotation[];
}

export async function getOemQuotation(id: string): Promise<(OemQuotation & { oem_name: string }) | null> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from('oem_quotations')
    .select('*, oem:oems(name)')
    .eq('id', id)
    .maybeSingle();
  if (error) throw new Error(`Could not load OEM quotation: ${error.message}`);
  if (!data) return null;
  return { ...(data as any), oem_name: (data as any).oem?.name ?? '—' };
}

export async function getOemQuotationItems(id: string): Promise<OemQuotationItem[]> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from('oem_quotation_items')
    .select('*')
    .eq('oem_quotation_id', id)
    .order('line_no');
  if (error) throw new Error(`Could not load OEM quotation items: ${error.message}`);
  return (data ?? []) as OemQuotationItem[];
}

export interface PurchaseOrderRow extends PurchaseOrder {
  oem_name: string;
  required_by_date: string | null;
  requirement_no: string | null;
}

export async function listPurchaseOrders(filters: { q?: string; status?: string } = {}): Promise<PurchaseOrderRow[]> {
  const supabase = createClient();
  let query = supabase
    .from('purchase_orders')
    .select('*, oem:oems(name), requirement:material_requirements(required_by_date, requirement_no)')
    .order('expected_delivery_date', { ascending: true, nullsFirst: false })
    .limit(300);
  if (filters.q) query = query.ilike('po_no', `%${filters.q.replace(/[%,]/g, ' ')}%`);
  if (filters.status) query = query.eq('status', filters.status);

  const { data, error } = await query;
  if (error) throw new Error(`Could not load purchase orders: ${error.message}`);
  return (data ?? []).map((r: any) => ({
    ...r,
    oem_name: r.oem?.name ?? '—',
    required_by_date: r.requirement?.required_by_date ?? null,
    requirement_no: r.requirement?.requirement_no ?? null,
  }));
}

export async function getPurchaseOrder(id: string): Promise<
  | (PurchaseOrder & { oem_name: string; required_by_date: string | null; requirement_no: string | null; customer_order_no: string | null })
  | null
> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from('purchase_orders')
    .select('*, oem:oems(name), requirement:material_requirements(required_by_date, requirement_no), customer_order:customer_orders(order_no)')
    .eq('id', id)
    .maybeSingle();
  if (error) throw new Error(`Could not load purchase order: ${error.message}`);
  if (!data) return null;
  return {
    ...(data as any),
    oem_name: (data as any).oem?.name ?? '—',
    required_by_date: (data as any).requirement?.required_by_date ?? null,
    requirement_no: (data as any).requirement?.requirement_no ?? null,
    customer_order_no: (data as any).customer_order?.order_no ?? null,
  };
}

export async function getPurchaseOrderItems(id: string): Promise<(PurchaseOrderItem & { product_name: string | null })[]> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from('purchase_order_items')
    .select('*, product:products(name,code)')
    .eq('purchase_order_id', id)
    .order('line_no');
  if (error) throw new Error(`Could not load PO items: ${error.message}`);
  return (data ?? []).map((r: any) => ({
    ...r,
    product_name: r.product ? `${r.product.code} — ${r.product.name}` : null,
  }));
}

export async function getPurchaseApprovals(poId: string): Promise<PurchaseApproval[]> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from('purchase_approvals')
    .select('*')
    .eq('purchase_order_id', poId)
    .order('step_no');
  if (error) throw new Error(`Could not load purchase approvals: ${error.message}`);
  return (data ?? []) as PurchaseApproval[];
}

export async function getMaterialReceipts(poId: string): Promise<MaterialReceipt[]> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from('material_receipts')
    .select('*')
    .eq('purchase_order_id', poId)
    .order('received_date', { ascending: false });
  if (error) throw new Error(`Could not load receipts: ${error.message}`);
  return (data ?? []) as MaterialReceipt[];
}

export async function getProcurementDocuments(entityType: string, entityId: string): Promise<ProcurementDocument[]> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from('procurement_documents')
    .select('*, document:documents(file_name,storage_path,classification)')
    .eq('entity_type', entityType)
    .eq('entity_id', entityId)
    .order('created_at', { ascending: false });
  if (error) throw new Error(`Could not load procurement documents: ${error.message}`);
  return (data ?? []).map((r: any) => ({
    id: r.id,
    entity_type: r.entity_type,
    entity_id: r.entity_id,
    document_id: r.document_id,
    doc_type: r.doc_type,
    expires_on: r.expires_on,
    file_name: r.document?.file_name ?? '—',
  }));
}

export async function getPurchaseRequestsForRequirement(requirementId: string): Promise<PurchaseRequestRef[]> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from('purchase_requests')
    .select('id, request_no, material_requirement_id, customer_order_id, needed_by, status')
    .eq('material_requirement_id', requirementId)
    .order('created_at');
  if (error) throw new Error(`Could not load purchase requests: ${error.message}`);
  return (data ?? []) as PurchaseRequestRef[];
}

/** Order lines whose inspection has passed (ready to dispatch). */
export async function getPdiRecordsForOrder(customerOrderId: string) {
  const supabase = createClient();
  const { data, error } = await supabase
    .from('pdi_records')
    .select('*, items:pdi_items(*)')
    .eq('customer_order_id', customerOrderId)
    .order('inspection_date', { ascending: false });
  if (error) throw new Error(`Could not load PDI records: ${error.message}`);
  return data ?? [];
}

export async function listCustomerOrderOptions(): Promise<
  { id: string; order_no: string; customer_id: string }[]
> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from('customer_orders')
    .select('id, order_no, customer_id')
    .order('order_date', { ascending: false })
    .limit(300);
  if (error) throw new Error(`Could not load customer orders: ${error.message}`);
  return (data ?? []) as { id: string; order_no: string; customer_id: string }[];
}

export async function getPdiRecordsForReceipts(receiptIds: string[]) {
  if (!receiptIds.length) return [] as { id: string; material_receipt_id: string; result: string }[];
  const supabase = createClient();
  const { data, error } = await supabase
    .from('pdi_records')
    .select('id, material_receipt_id, result')
    .in('material_receipt_id', receiptIds);
  if (error) throw new Error(`Could not load PDI records: ${error.message}`);
  return (data ?? []) as { id: string; material_receipt_id: string; result: string }[];
}
