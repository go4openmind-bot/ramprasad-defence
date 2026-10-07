'use server';

import { redirect } from 'next/navigation';
import { revalidatePath } from 'next/cache';
import { createClient } from '@/lib/supabase/server';
import { getCurrentContext } from '@/lib/data';
import { fieldErrors, quotationItemSchema, quotationSchema } from '@/lib/validation';
import { parseQuotationStatus } from '@/lib/quotation';

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

function headerFromForm(formData: FormData) {
  return quotationSchema.safeParse({
    customer_id: formData.get('customer_id'),
    tender_id: formData.get('tender_id'),
    opportunity_id: formData.get('opportunity_id'),
    quote_date: formData.get('quote_date'),
    validity_date: formData.get('validity_date'),
    currency: formData.get('currency') || 'INR',
    payment_terms: formData.get('payment_terms'),
    delivery_terms: formData.get('delivery_terms'),
    warranty: formData.get('warranty'),
    notes: formData.get('notes'),
    status: formData.get('status') || 'draft',
  });
}

async function nextVersion(quotationNo: string): Promise<number> {
  const supabase = createClient();
  const { data } = await supabase
    .from('quotations')
    .select('version')
    .eq('quotation_no', quotationNo)
    .order('version', { ascending: false })
    .limit(1)
    .maybeSingle();
  return (data?.version ?? 0) + 1;
}

export async function createQuotation(formData: FormData) {
  const parsed = headerFromForm(formData);
  if (!parsed.success) fail('/quotations/new', firstError(fieldErrors(parsed.error)));

  const supabase = createClient();
  const { count } = await supabase.from('quotations').select('id', { count: 'exact', head: true });
  const quotationNo = String(formData.get('quotation_no') || '').trim() || `QTN-${String((count ?? 0) + 1).padStart(4, '0')}`;

  const { data, error } = await supabase
    .from('quotations')
    .insert({ ...clean(parsed.data), quotation_no: quotationNo, version: 1, status: 'draft' })
    .select('id')
    .single();
  if (error) fail('/quotations/new', `Could not create the quotation: ${error.message}`);

  revalidatePath('/quotations');
  redirect(`/quotations/${data!.id}`);
}

export async function updateQuotationHeader(formData: FormData) {
  const id = String(formData.get('id') ?? '');
  if (!id) fail('/quotations', 'Missing quotation id.');

  const parsed = headerFromForm(formData);
  if (!parsed.success) fail(`/quotations/${id}/edit`, firstError(fieldErrors(parsed.error)));

  const supabase = createClient();
  const { error } = await supabase.from('quotations').update(clean(parsed.data)).eq('id', id);
  if (error) fail(`/quotations/${id}/edit`, error.message);

  revalidatePath(`/quotations/${id}`);
  redirect(`/quotations/${id}`);
}

export async function setQuotationStatus(formData: FormData) {
  const id = String(formData.get('id') ?? '');
  const status = parseQuotationStatus(formData.get('status'));
  if (!id) fail('/quotations', 'Missing quotation id.');

  const supabase = createClient();
  const { error } = await supabase.from('quotations').update({ status }).eq('id', id);
  if (error) fail(`/quotations/${id}`, error.message);

  revalidatePath(`/quotations/${id}`);
  redirect(`/quotations/${id}`);
}

export async function submitForApproval(formData: FormData) {
  const id = String(formData.get('id') ?? '');
  const supabase = createClient();

  const { count } = await supabase
    .from('quotation_items')
    .select('id', { count: 'exact', head: true })
    .eq('quotation_id', id);
  if (!count) fail(`/quotations/${id}`, 'Add at least one product line before submitting for approval.');

  const { error } = await supabase.from('quotations').update({ status: 'pending_approval' }).eq('id', id);
  if (error) fail(`/quotations/${id}`, error.message);

  revalidatePath(`/quotations/${id}`);
  redirect(`/quotations/${id}`);
}

export async function decideQuotation(formData: FormData) {
  const id = String(formData.get('id') ?? '');
  const decision = String(formData.get('decision') ?? '');
  const comments = String(formData.get('comments') ?? '').trim() || null;
  if (!id) fail('/quotations', 'Missing quotation id.');
  if (decision !== 'approved' && decision !== 'rejected') fail(`/quotations/${id}`, 'Unknown decision.');

  const me = await getCurrentContext();
  if (!me || !(me.roles.includes('admin') || me.roles.includes('management'))) {
    fail(`/quotations/${id}`, 'Only management or an administrator can approve a quotation.');
  }

  const supabase = createClient();
  const { count } = await supabase
    .from('quotation_approvals')
    .select('id', { count: 'exact', head: true })
    .eq('quotation_id', id);

  const { error: insError } = await supabase.from('quotation_approvals').insert({
    quotation_id: id,
    step_no: (count ?? 0) + 1,
    approver_user_id: me!.id,
    decision,
    comments,
    decided_at: new Date().toISOString(),
  });
  if (insError) fail(`/quotations/${id}`, insError.message);

  const { error } = await supabase
    .from('quotations')
    .update({
      status: decision,
      approved_by: me!.id,
      approved_at: new Date().toISOString(),
    })
    .eq('id', id);
  if (error) fail(`/quotations/${id}`, error.message);

  revalidatePath(`/quotations/${id}`);
  redirect(`/quotations/${id}`);
}

export async function addQuotationItem(formData: FormData) {
  const quotationId = String(formData.get('quotation_id') ?? '');
  if (!quotationId) fail('/quotations', 'Missing quotation id.');

  const parsed = quotationItemSchema.safeParse({
    description: formData.get('description'),
    quantity: formData.get('quantity'),
    unit: formData.get('unit') || 'NO',
    unit_price: formData.get('unit_price'),
    discount_pct: formData.get('discount_pct'),
    tax_pct: formData.get('tax_pct'),
    purchase_unit_cost: formData.get('purchase_unit_cost'),
    logistics_unit_cost: formData.get('logistics_unit_cost'),
    other_unit_cost: formData.get('other_unit_cost'),
    product_id: formData.get('product_id'),
    source_oem_id: formData.get('source_oem_id'),
    tender_requirement_id: formData.get('tender_requirement_id'),
    technical_compliance: formData.get('technical_compliance') || 'pending',
  });
  if (!parsed.success) fail(`/quotations/${quotationId}`, firstError(fieldErrors(parsed.error)));

  const supabase = createClient();
  const { data: last } = await supabase
    .from('quotation_items')
    .select('line_no')
    .eq('quotation_id', quotationId)
    .order('line_no', { ascending: false })
    .limit(1)
    .maybeSingle();

  const { error } = await supabase.from('quotation_items').insert({
    quotation_id: quotationId,
    line_no: (last?.line_no ?? 0) + 1,
    ...clean(parsed.data),
  });
  if (error) fail(`/quotations/${quotationId}`, error.message);

  revalidatePath(`/quotations/${quotationId}`);
  redirect(`/quotations/${quotationId}`);
}

export async function removeQuotationItem(formData: FormData) {
  const quotationId = String(formData.get('quotation_id') ?? '');
  const itemId = String(formData.get('item_id') ?? '');
  const supabase = createClient();
  const { error } = await supabase.from('quotation_items').delete().eq('id', itemId);
  if (error) fail(`/quotations/${quotationId}`, error.message);

  revalidatePath(`/quotations/${quotationId}`);
  redirect(`/quotations/${quotationId}`);
}

export async function createRevision(formData: FormData) {
  const id = String(formData.get('quotation_id') ?? '');
  if (!id) fail('/quotations', 'Missing quotation id.');

  const supabase = createClient();
  const { data: original, error: loadError } = await supabase
    .from('quotations')
    .select('*')
    .eq('id', id)
    .maybeSingle();
  if (loadError || !original) fail('/quotations', `Could not load the quotation: ${loadError?.message ?? 'not found'}`);

  const version = await nextVersion(original!.quotation_no);

  const { data: created, error: createError } = await supabase
    .from('quotations')
    .insert({
      quotation_no: original!.quotation_no,
      version,
      customer_id: original!.customer_id,
      tender_id: original!.tender_id,
      opportunity_id: original!.opportunity_id,
      quote_date: new Date().toISOString().slice(0, 10),
      validity_date: original!.validity_date,
      currency: original!.currency,
      payment_terms: original!.payment_terms,
      delivery_terms: original!.delivery_terms,
      warranty: original!.warranty,
      notes: original!.notes,
      revision_of: original!.id,
      status: 'draft',
    })
    .select('id')
    .single();
  if (createError) fail(`/quotations/${id}`, `Could not create the revision: ${createError.message}`);

  const { data: items } = await supabase
    .from('quotation_items')
    .select('*')
    .eq('quotation_id', id)
    .order('line_no');

  if (items && items.length) {
    const rows = items.map((i: any) => ({
      quotation_id: created!.id,
      line_no: i.line_no,
      product_id: i.product_id,
      tender_requirement_id: i.tender_requirement_id,
      source_oem_id: i.source_oem_id,
      description: i.description,
      quantity: i.quantity,
      unit: i.unit,
      unit_price: i.unit_price,
      discount_pct: i.discount_pct,
      tax_pct: i.tax_pct,
      purchase_unit_cost: i.purchase_unit_cost,
      logistics_unit_cost: i.logistics_unit_cost,
      other_unit_cost: i.other_unit_cost,
      technical_compliance: i.technical_compliance,
    }));
    const { error: copyError } = await supabase.from('quotation_items').insert(rows);
    if (copyError) fail(`/quotations/${id}`, `Revision created but lines failed to copy: ${copyError.message}`);
  }

  if (original!.status === 'approved' || original!.status === 'submitted') {
    await supabase.from('quotations').update({ status: 'revised' }).eq('id', id);
  }

  revalidatePath(`/quotations/${id}`);
  redirect(`/quotations/${created!.id}`);
}

export async function addFollowUpTask(formData: FormData) {
  const quotationId = String(formData.get('quotation_id') ?? '');
  const title = String(formData.get('title') ?? '').trim();
  const assignedTo = String(formData.get('assigned_to') ?? '');
  const dueDate = String(formData.get('due_date') ?? '');
  if (!quotationId) fail('/quotations', 'Missing quotation id.');
  if (!title) fail(`/quotations/${quotationId}`, 'A follow-up task needs a title.');

  const supabase = createClient();
  const { error } = await supabase.from('tasks').insert({
    title,
    entity_table: 'quotations',
    entity_id: quotationId,
    assigned_to: assignedTo || null,
    due_date: dueDate || null,
    priority: 'medium',
  });
  if (error) fail(`/quotations/${quotationId}`, error.message);

  revalidatePath(`/quotations/${quotationId}`);
  redirect(`/quotations/${quotationId}`);
}
