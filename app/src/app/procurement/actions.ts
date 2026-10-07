'use server';

import { redirect } from 'next/navigation';
import { revalidatePath } from 'next/cache';
import { createClient } from '@/lib/supabase/server';
import { getCurrentContext } from '@/lib/data';
import {
  expectedDeliverySchema,
  fieldErrors,
  materialReceiptSchema,
  materialRequirementItemSchema,
  materialRequirementSchema,
  oemQuotationSchema,
  pdiSchema,
} from '@/lib/validation';

function clean<T extends Record<string, unknown>>(input: T): Partial<T> {
  return Object.fromEntries(Object.entries(input).filter(([, v]) => v !== undefined)) as Partial<T>;
}

function fail(path: string, message: string): never {
  const sep = path.includes('?') ? '&' : '?';
  redirect(`${path}${sep}error=${encodeURIComponent(message)}`);
}

function firstError(errors: Record<string, string>): string {
  const values = Object.values(errors);
  return values.length ? values.join(' ') : 'Please check the form and try again.';
}

async function nextNo(table: string, prefix: string): Promise<string> {
  const supabase = createClient();
  const { count } = await supabase.from(table).select('id', { count: 'exact', head: true });
  return `${prefix}-${String((count ?? 0) + 1).padStart(4, '0')}`;
}

// --- Stage 1: material requirement -----------------------------------------

export async function createMaterialRequirement(formData: FormData) {
  const parsed = materialRequirementSchema.safeParse({
    requirement_no: formData.get('requirement_no'),
    customer_order_id: formData.get('customer_order_id'),
    requested_by: formData.get('requested_by'),
    required_by_date: formData.get('required_by_date'),
    priority: formData.get('priority') || 'medium',
    notes: formData.get('notes'),
  });
  if (!parsed.success) fail('/procurement/requirements/new', firstError(fieldErrors(parsed.error)));

  const supabase = createClient();
  const requirementNo = parsed.data.requirement_no || (await nextNo('material_requirements', 'MR'));
  const { data, error } = await supabase
    .from('material_requirements')
    .insert({ ...clean(parsed.data), requirement_no: requirementNo, status: 'open' })
    .select('id')
    .single();
  if (error) fail('/procurement/requirements/new', `Could not create the requirement: ${error.message}`);

  revalidatePath('/procurement');
  redirect(`/procurement/requirements/${data!.id}`);
}

export async function addMaterialRequirementItem(formData: FormData) {
  const requirementId = String(formData.get('requirement_id') ?? '');
  const parsed = materialRequirementItemSchema.safeParse({
    description: formData.get('description'),
    quantity: formData.get('quantity'),
    unit: formData.get('unit') || 'NO',
    product_id: formData.get('product_id'),
    required_by: formData.get('required_by'),
  });
  if (!parsed.success) fail(`/procurement/requirements/${requirementId}`, firstError(fieldErrors(parsed.error)));

  const supabase = createClient();
  const { data: last } = await supabase
    .from('material_requirement_items')
    .select('line_no')
    .eq('material_requirement_id', requirementId)
    .order('line_no', { ascending: false })
    .limit(1)
    .maybeSingle();

  const { error } = await supabase.from('material_requirement_items').insert({
    material_requirement_id: requirementId,
    line_no: (last?.line_no ?? 0) + 1,
    ...clean(parsed.data),
  });
  if (error) fail(`/procurement/requirements/${requirementId}`, error.message);

  revalidatePath(`/procurement/requirements/${requirementId}`);
  redirect(`/procurement/requirements/${requirementId}`);
}

// --- Stage 2: purchase request ---------------------------------------------

export async function createPurchaseRequest(formData: FormData) {
  const requirementId = String(formData.get('requirement_id') ?? '');
  const supabase = createClient();

  const { data: requirement } = await supabase
    .from('material_requirements')
    .select('*')
    .eq('id', requirementId)
    .maybeSingle();
  if (!requirement) fail('/procurement', 'Material requirement not found.');

  const { data: items } = await supabase
    .from('material_requirement_items')
    .select('*')
    .eq('material_requirement_id', requirementId)
    .order('line_no');

  const requestNo = await nextNo('purchase_requests', 'PR');
  const { data: pr, error } = await supabase
    .from('purchase_requests')
    .insert({
      request_no: requestNo,
      material_requirement_id: requirementId,
      customer_order_id: requirement!.customer_order_id,
      needed_by: requirement!.required_by_date,
      status: 'submitted',
      priority: requirement!.priority,
    })
    .select('id')
    .single();
  if (error) fail(`/procurement/requirements/${requirementId}`, error.message);

  if (items && items.length) {
    const rows = items.map((i: any) => ({
      purchase_request_id: pr!.id,
      line_no: i.line_no,
      product_id: i.product_id,
      description: i.description,
      quantity: i.quantity,
      unit: i.unit,
      required_by: i.required_by,
    }));
    const { error: itemError } = await supabase.from('purchase_request_items').insert(rows);
    if (itemError) fail(`/procurement/requirements/${requirementId}`, itemError.message);
  }

  await supabase.from('material_requirements').update({ status: 'sourcing' }).eq('id', requirementId);

  revalidatePath(`/procurement/requirements/${requirementId}`);
  redirect(`/procurement/requirements/${requirementId}`);
}

// --- Stage 3: OEM RFQ -------------------------------------------------------

export async function createOemRfqs(formData: FormData) {
  const requirementId = String(formData.get('requirement_id') ?? '');
  const oemIds = formData.getAll('oem_ids').map(String).filter(Boolean);
  const dueDate = String(formData.get('due_date') ?? '');
  if (oemIds.length === 0) fail(`/procurement/requirements/${requirementId}`, 'Select at least one OEM.');

  const supabase = createClient();
  const { data: items } = await supabase
    .from('material_requirement_items')
    .select('*')
    .eq('material_requirement_id', requirementId)
    .order('line_no');
  if (!items || items.length === 0) fail(`/procurement/requirements/${requirementId}`, 'Add requirement lines first.');

  const { data: requirement } = await supabase
    .from('material_requirements')
    .select('*')
    .eq('id', requirementId)
    .maybeSingle();

  const rfqNo = await nextNo('oem_rfqs', 'RFQ');

  for (const oemId of oemIds) {
    const { data: rfq, error } = await supabase
      .from('oem_rfqs')
      .insert({
        rfq_no: rfqNo,
        oem_id: oemId,
        material_requirement_id: requirementId,
        sent_date: new Date().toISOString().slice(0, 10),
        due_date: dueDate || null,
        status: 'sent',
      })
      .select('id')
      .single();
    if (error) fail(`/procurement/requirements/${requirementId}`, `RFQ failed: ${error.message}`);

    const rfqItems = items.map((i: any) => ({
      oem_rfq_id: rfq!.id,
      line_no: i.line_no,
      product_id: i.product_id,
      material_requirement_item_id: i.id,
      description: i.description,
      quantity: i.quantity,
      unit: i.unit,
    }));
    const { error: itemError } = await supabase.from('oem_rfq_items').insert(rfqItems);
    if (itemError) fail(`/procurement/requirements/${requirementId}`, itemError.message);
  }

  await supabase.from('material_requirements').update({ status: 'rfq_sent' }).eq('id', requirementId);

  revalidatePath(`/procurement/requirements/${requirementId}`);
  redirect(`/procurement/requirements/${requirementId}`);
}

// --- Stage 4: OEM quotation -------------------------------------------------

export async function recordOemQuotation(formData: FormData) {
  const rfqId = String(formData.get('oem_rfq_id') ?? '');
  const parsed = oemQuotationSchema.safeParse({
    oem_rfq_id: rfqId,
    oem_id: formData.get('oem_id'),
    quote_date: formData.get('quote_date'),
    validity_date: formData.get('validity_date'),
    currency: formData.get('currency') || 'INR',
    payment_terms: formData.get('payment_terms'),
    delivery_terms: formData.get('delivery_terms'),
    warranty: formData.get('warranty'),
    lead_time_days: formData.get('lead_time_days'),
    notes: formData.get('notes'),
  });
  if (!parsed.success) fail(`/procurement/rfqs/${rfqId}`, firstError(fieldErrors(parsed.error)));

  const supabase = createClient();
  const { data: rfqItems } = await supabase.from('oem_rfq_items').select('*').eq('oem_rfq_id', rfqId).order('line_no');
  if (!rfqItems || rfqItems.length === 0) fail(`/procurement/rfqs/${rfqId}`, 'This RFQ has no lines.');

  const quotationNo = await nextNo('oem_quotations', 'OEMQ');
  const { data: quote, error } = await supabase
    .from('oem_quotations')
    .insert({ ...clean(parsed.data), quotation_no: quotationNo, status: 'received' })
    .select('id')
    .single();
  if (error) fail(`/procurement/rfqs/${rfqId}`, error.message);

  const rows = rfqItems.map((i: any) => ({
    oem_quotation_id: quote!.id,
    line_no: i.line_no,
    oem_rfq_item_id: i.id,
    product_id: i.product_id,
    description: i.description,
    quantity: i.quantity,
    unit: i.unit,
    unit_price: Number(formData.get(`price_${i.id}`) ?? 0) || 0,
    tax_pct: Number(formData.get(`tax_${i.id}`) ?? 18) || 0,
  }));
  const { error: itemError } = await supabase.from('oem_quotation_items').insert(rows);
  if (itemError) fail(`/procurement/rfqs/${rfqId}`, itemError.message);

  await supabase.from('oem_rfqs').update({ status: 'quotes_received' }).eq('id', rfqId);

  const { data: rfq } = await supabase.from('oem_rfqs').select('material_requirement_id').eq('id', rfqId).maybeSingle();
  if (rfq?.material_requirement_id) {
    await supabase.from('material_requirements').update({ status: 'quoted' }).eq('id', rfq.material_requirement_id);
  }

  revalidatePath(`/procurement/rfqs/${rfqId}`);
  redirect(`/procurement/rfqs/${rfqId}`);
}

// --- Stage 5: OEM selection -> purchase order -------------------------------

export async function selectOemQuotation(formData: FormData) {
  const quotationId = String(formData.get('quotation_id') ?? '');
  const supabase = createClient();

  const { data: quote } = await supabase.from('oem_quotations').select('*').eq('id', quotationId).maybeSingle();
  if (!quote) fail('/procurement', 'OEM quotation not found.');

  const { data: items } = await supabase
    .from('oem_quotation_items')
    .select('*')
    .eq('oem_quotation_id', quotationId)
    .order('line_no');

  const { data: rfq } = quote!.oem_rfq_id
    ? await supabase.from('oem_rfqs').select('*').eq('id', quote!.oem_rfq_id).maybeSingle()
    : { data: null } as any;

  const { data: requirement } = rfq?.material_requirement_id
    ? await supabase.from('material_requirements').select('*').eq('id', rfq.material_requirement_id).maybeSingle()
    : { data: null } as any;

  // mark selection
  await supabase
    .from('oem_quotations')
    .update({ status: 'selected', selected_at: new Date().toISOString() })
    .eq('id', quotationId);
  if (quote!.oem_rfq_id) {
    await supabase
      .from('oem_quotations')
      .update({ status: 'rejected' })
      .eq('oem_rfq_id', quote!.oem_rfq_id)
      .neq('id', quotationId)
      .eq('status', 'received');
  }

  // expected delivery from lead time
  let expected: string | null = null;
  if (quote!.lead_time_days != null) {
    const d = new Date(`${quote!.quote_date}T00:00:00Z`);
    d.setUTCDate(d.getUTCDate() + Number(quote!.lead_time_days));
    expected = d.toISOString().slice(0, 10);
  }

  const poNo = await nextNo('purchase_orders', 'PO');
  const { data: po, error } = await supabase
    .from('purchase_orders')
    .insert({
      po_no: poNo,
      oem_id: quote!.oem_id,
      customer_order_id: requirement?.customer_order_id ?? null,
      purchase_request_id: rfq?.purchase_request_id ?? null,
      oem_quotation_id: quote!.id,
      material_requirement_id: requirement?.id ?? null,
      currency: quote!.currency,
      expected_delivery_date: expected,
      payment_terms: quote!.payment_terms,
      warranty: quote!.warranty,
      status: 'pending_approval',
    })
    .select('id')
    .single();
  if (error) fail(`/procurement/quotations/${quotationId}`, error.message);

  if (items && items.length) {
    const rows = items.map((i: any) => ({
      purchase_order_id: po!.id,
      line_no: i.line_no,
      product_id: i.product_id,
      description: i.description,
      quantity: i.quantity,
      unit: i.unit,
      unit_price: i.unit_price,
      tax_pct: i.tax_pct,
    }));
    const { error: itemError } = await supabase.from('purchase_order_items').insert(rows);
    if (itemError) fail(`/procurement/quotations/${quotationId}`, itemError.message);
  }

  if (requirement?.id) {
    await supabase.from('material_requirements').update({ status: 'ordered' }).eq('id', requirement.id);
  }

  revalidatePath('/procurement');
  redirect(`/procurement/orders/${po!.id}`);
}

// --- Stage 6: purchase approval --------------------------------------------

export async function decidePurchaseOrder(formData: FormData) {
  const poId = String(formData.get('purchase_order_id') ?? '');
  const decision = String(formData.get('decision') ?? '');
  const comments = String(formData.get('comments') ?? '').trim() || null;
  if (decision !== 'approved' && decision !== 'rejected') fail(`/procurement/orders/${poId}`, 'Unknown decision.');

  const me = await getCurrentContext();
  if (!me || !(me.roles.includes('admin') || me.roles.includes('management'))) {
    fail(`/procurement/orders/${poId}`, 'Only management or an administrator can approve a purchase order.');
  }

  const supabase = createClient();
  const { count } = await supabase
    .from('purchase_approvals')
    .select('id', { count: 'exact', head: true })
    .eq('purchase_order_id', poId);

  const { error: insError } = await supabase.from('purchase_approvals').insert({
    purchase_order_id: poId,
    step_no: (count ?? 0) + 1,
    approver_user_id: me!.id,
    decision,
    comments,
    decided_at: new Date().toISOString(),
  });
  if (insError) fail(`/procurement/orders/${poId}`, insError.message);

  if (decision === 'approved') {
    const { error } = await supabase
      .from('purchase_orders')
      .update({ status: 'approved', approved_by: me!.id, approved_at: new Date().toISOString() })
      .eq('id', poId);
    if (error) fail(`/procurement/orders/${poId}`, error.message);
  }

  revalidatePath(`/procurement/orders/${poId}`);
  redirect(`/procurement/orders/${poId}`);
}

// --- Stage 7: expected delivery / terms ------------------------------------

export async function setExpectedDelivery(formData: FormData) {
  const poId = String(formData.get('purchase_order_id') ?? '');
  const parsed = expectedDeliverySchema.safeParse({
    expected_delivery_date: formData.get('expected_delivery_date'),
    payment_terms: formData.get('payment_terms'),
    warranty: formData.get('warranty'),
  });
  if (!parsed.success) fail(`/procurement/orders/${poId}`, firstError(fieldErrors(parsed.error)));

  const supabase = createClient();
  const { error } = await supabase.from('purchase_orders').update(clean(parsed.data)).eq('id', poId);
  if (error) fail(`/procurement/orders/${poId}`, error.message);

  revalidatePath(`/procurement/orders/${poId}`);
  redirect(`/procurement/orders/${poId}`);
}

// --- Stage 8: material receipt ---------------------------------------------

export async function recordMaterialReceipt(formData: FormData) {
  const poId = String(formData.get('purchase_order_id') ?? '');
  const parsed = materialReceiptSchema.safeParse({
    received_date: formData.get('received_date'),
    docket_no: formData.get('docket_no'),
    notes: formData.get('notes'),
  });
  if (!parsed.success) fail(`/procurement/orders/${poId}`, firstError(fieldErrors(parsed.error)));

  const supabase = createClient();
  const { data: po } = await supabase.from('purchase_orders').select('*').eq('id', poId).maybeSingle();
  if (!po) fail('/procurement', 'Purchase order not found.');

  const grnNo = await nextNo('material_receipts', 'GRN');
  const { data: receipt, error } = await supabase
    .from('material_receipts')
    .insert({
      grn_no: grnNo,
      purchase_order_id: poId,
      oem_id: po!.oem_id,
      received_date: parsed.data.received_date,
      docket_no: parsed.data.docket_no ?? null,
      status: 'received',
      inspection_status: 'pending',
      notes: parsed.data.notes ?? null,
    })
    .select('id')
    .single();
  if (error) fail(`/procurement/orders/${poId}`, error.message);

  const { data: poItems } = await supabase
    .from('purchase_order_items')
    .select('*')
    .eq('purchase_order_id', poId)
    .order('line_no');

  if (poItems && poItems.length) {
    const rows = poItems
      .map((i: any) => ({
        material_receipt_id: receipt!.id,
        purchase_order_item_id: i.id,
        product_id: i.product_id,
        qty_received: Number(formData.get(`qty_${i.id}`) ?? 0) || 0,
        qty_accepted: Number(formData.get(`qty_${i.id}`) ?? 0) || 0,
      }))
      .filter((r) => r.qty_received > 0);
    if (rows.length) {
      const { error: itemError } = await supabase.from('material_receipt_items').insert(rows);
      if (itemError) fail(`/procurement/orders/${poId}`, itemError.message);
    }
  }

  revalidatePath(`/procurement/orders/${poId}`);
  redirect(`/procurement/orders/${poId}`);
}

// --- Stage 9: PDI -----------------------------------------------------------

export async function createPdi(formData: FormData) {
  const receiptId = String(formData.get('material_receipt_id') ?? '');
  const poId = String(formData.get('purchase_order_id') ?? '');
  const parsed = pdiSchema.safeParse({
    inspection_type: formData.get('inspection_type') || 'pdi',
    result: formData.get('result') || 'pending',
    certificate_no: formData.get('certificate_no'),
    agency: formData.get('agency'),
    notes: formData.get('notes'),
  });
  if (!parsed.success) fail(`/procurement/orders/${poId}`, firstError(fieldErrors(parsed.error)));

  const supabase = createClient();
  const { data: receipt } = await supabase.from('material_receipts').select('*').eq('id', receiptId).maybeSingle();
  if (!receipt) fail('/procurement', 'Receipt not found.');

  const { data: po } = await supabase
    .from('purchase_orders')
    .select('id, customer_order_id')
    .eq('id', receipt!.purchase_order_id)
    .maybeSingle();

  const pdiNo = await nextNo('pdi_records', 'PDI');
  const { data: pdi, error } = await supabase
    .from('pdi_records')
    .insert({
      pdi_no: pdiNo,
      material_receipt_id: receiptId,
      customer_order_id: po?.customer_order_id ?? null,
      inspection_type: parsed.data.inspection_type,
      result: parsed.data.result,
      certificate_no: parsed.data.certificate_no ?? null,
      agency: parsed.data.agency ?? null,
      notes: parsed.data.notes ?? null,
    })
    .select('id')
    .single();
  if (error) fail(`/procurement/orders/${poId}`, error.message);

  const { data: receiptItems } = await supabase
    .from('material_receipt_items')
    .select('*')
    .eq('material_receipt_id', receiptId);

  if (receiptItems && receiptItems.length) {
    const passed = parsed.data.result === 'pass';
    const rows = receiptItems.map((i: any) => ({
      pdi_record_id: pdi!.id,
      material_receipt_item_id: i.id,
      product_id: i.product_id,
      qty_inspected: i.qty_received,
      qty_passed: passed ? i.qty_received : 0,
      qty_failed: passed ? 0 : i.qty_received,
    }));
    const { error: itemError } = await supabase.from('pdi_items').insert(rows);
    if (itemError) fail(`/procurement/orders/${poId}`, itemError.message);
  }

  await supabase
    .from('material_receipts')
    .update({ inspection_status: parsed.data.result === 'pass' ? 'passed' : parsed.data.result === 'fail' ? 'failed' : 'in_progress' })
    .eq('id', receiptId);

  revalidatePath(`/procurement/orders/${poId}`);
  redirect(`/procurement/orders/${poId}`);
}

// --- Compliance documents ---------------------------------------------------

export async function uploadProcurementDocument(formData: FormData) {
  const entityType = String(formData.get('entity_type') ?? 'purchase_order');
  const entityId = String(formData.get('entity_id') ?? '');
  const docType = String(formData.get('doc_type') ?? 'other');
  const expiresOn = String(formData.get('expires_on') ?? '');
  const redirectTo = String(formData.get('redirect_to') ?? '/procurement');
  const file = formData.get('file') as File | null;

  if (!file || file.size === 0) fail(redirectTo, 'Choose a file to upload.');
  if (file!.size > 10 * 1024 * 1024) fail(redirectTo, 'File is larger than 10 MB.');

  const supabase = createClient();
  const bucket = process.env.SUPABASE_DOCUMENTS_BUCKET || 'documents';
  const safeName = file!.name.replace(/[^a-zA-Z0-9._-]/g, '_');
  const storagePath = `procurement/${entityType}/${entityId}/${Date.now()}_${safeName}`;

  const upload = await supabase.storage.from(bucket).upload(storagePath, file!, {
    upsert: false,
    contentType: file!.type || 'application/octet-stream',
  });
  if (upload.error) fail(redirectTo, `Upload failed: ${upload.error.message}`);

  const { data: doc, error: docError } = await supabase
    .from('documents')
    .insert({
      file_name: file!.name,
      storage_bucket: bucket,
      storage_path: storagePath,
      mime_type: file!.type || null,
      size_bytes: file!.size,
      classification: 'internal',
      entity_table: entityType,
      entity_id: entityId,
    })
    .select('id')
    .single();
  if (docError) fail(redirectTo, `Could not record the document: ${docError.message}`);

  const { error: linkError } = await supabase.from('procurement_documents').insert({
    entity_type: entityType,
    entity_id: entityId,
    document_id: doc!.id,
    doc_type: docType,
    expires_on: expiresOn || null,
  });
  if (linkError) fail(redirectTo, `Could not link the document: ${linkError.message}`);

  revalidatePath(redirectTo, 'page');
  redirect(redirectTo);
}
