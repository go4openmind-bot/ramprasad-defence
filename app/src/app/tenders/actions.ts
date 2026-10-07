'use server';

import { redirect } from 'next/navigation';
import { revalidatePath } from 'next/cache';
import { createClient } from '@/lib/supabase/server';
import { fieldErrors, noteSchema, requirementSchema, taskSchema, tenderSchema } from '@/lib/validation';
import { parseStatus } from '@/lib/tenderStatus';

/** Drop undefined keys so PostgREST does not receive them. */
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

function tenderFromForm(formData: FormData) {
  return tenderSchema.safeParse({
    tender_no: formData.get('tender_no'),
    customer_id: formData.get('customer_id'),
    title: formData.get('title'),
    description: formData.get('description'),
    source: formData.get('source'),
    category: formData.get('category'),
    received_date: formData.get('received_date'),
    bid_due_date: formData.get('bid_due_date'),
    emd_amount: formData.get('emd_amount'),
    currency: formData.get('currency') || 'INR',
    priority: formData.get('priority') || 'medium',
    status: formData.get('status') || 'new',
    owner_user_id: formData.get('owner_user_id'),
    notes: formData.get('notes'),
  });
}

export async function createTender(formData: FormData) {
  const parsed = tenderFromForm(formData);
  if (!parsed.success) fail('/tenders/new', firstError(fieldErrors(parsed.error)));

  const supabase = createClient();
  const { data, error } = await supabase
    .from('tenders')
    .insert(clean(parsed.data))
    .select('id')
    .single();

  if (error) fail('/tenders/new', `Could not save the tender: ${error.message}`);

  revalidatePath('/tenders');
  redirect(`/tenders/${data!.id}`);
}

export async function updateTender(formData: FormData) {
  const id = String(formData.get('id') ?? '');
  if (!id) fail('/tenders', 'Missing tender id.');

  const parsed = tenderFromForm(formData);
  if (!parsed.success) fail(`/tenders/${id}/edit`, firstError(fieldErrors(parsed.error)));

  const supabase = createClient();
  const { error } = await supabase.from('tenders').update(clean(parsed.data)).eq('id', id);
  if (error) fail(`/tenders/${id}/edit`, `Could not update the tender: ${error.message}`);

  revalidatePath(`/tenders/${id}`);
  redirect(`/tenders/${id}`);
}

export async function setTenderStatus(formData: FormData) {
  const id = String(formData.get('id') ?? '');
  const status = parseStatus(formData.get('status'));
  if (!id) fail('/tenders', 'Missing tender id.');

  const supabase = createClient();
  const { error } = await supabase.from('tenders').update({ status }).eq('id', id);
  if (error) fail(`/tenders/${id}`, `Could not change status: ${error.message}`);

  revalidatePath(`/tenders/${id}`);
  revalidatePath('/tenders');
  redirect(`/tenders/${id}`);
}

export async function assignTender(formData: FormData) {
  const id = String(formData.get('id') ?? '');
  const owner = String(formData.get('owner_user_id') ?? '');
  if (!id) fail('/tenders', 'Missing tender id.');

  const supabase = createClient();
  const { error } = await supabase
    .from('tenders')
    .update({ owner_user_id: owner || null })
    .eq('id', id);
  if (error) fail(`/tenders/${id}`, `Could not assign: ${error.message}`);

  revalidatePath(`/tenders/${id}`);
  redirect(`/tenders/${id}`);
}

export async function addRequirement(formData: FormData) {
  const tenderId = String(formData.get('tender_id') ?? '');
  if (!tenderId) fail('/tenders', 'Missing tender id.');

  const parsed = requirementSchema.safeParse({
    description: formData.get('description'),
    specification: formData.get('specification'),
    quantity: formData.get('quantity'),
    unit: formData.get('unit') || 'NO',
  });
  if (!parsed.success) fail(`/tenders/${tenderId}`, firstError(fieldErrors(parsed.error)));

  const supabase = createClient();
  const { data: last } = await supabase
    .from('tender_requirements')
    .select('line_no')
    .eq('tender_id', tenderId)
    .order('line_no', { ascending: false })
    .limit(1)
    .maybeSingle();
  const lineNo = (last?.line_no ?? 0) + 1;

  const { error } = await supabase.from('tender_requirements').insert({
    tender_id: tenderId,
    line_no: lineNo,
    ...parsed.data,
  });
  if (error) fail(`/tenders/${tenderId}`, `Could not add the requirement: ${error.message}`);

  revalidatePath(`/tenders/${tenderId}`);
  redirect(`/tenders/${tenderId}`);
}

export async function addNote(formData: FormData) {
  const tenderId = String(formData.get('tender_id') ?? '');
  const parsed = noteSchema.safeParse({ note: formData.get('note') });
  if (!parsed.success) fail(`/tenders/${tenderId}`, firstError(fieldErrors(parsed.error)));

  const supabase = createClient();
  const { error } = await supabase
    .from('tender_notes')
    .insert({ tender_id: tenderId, note: parsed.data.note });
  if (error) fail(`/tenders/${tenderId}`, `Could not add the note: ${error.message}`);

  revalidatePath(`/tenders/${tenderId}`);
  redirect(`/tenders/${tenderId}`);
}

export async function addTask(formData: FormData) {
  const tenderId = String(formData.get('tender_id') ?? '');
  const parsed = taskSchema.safeParse({
    title: formData.get('title'),
    assigned_to: formData.get('assigned_to'),
    due_date: formData.get('due_date'),
    priority: formData.get('priority') || 'medium',
  });
  if (!parsed.success) fail(`/tenders/${tenderId}`, firstError(fieldErrors(parsed.error)));

  const supabase = createClient();
  const { error } = await supabase.from('tasks').insert({
    ...clean(parsed.data),
    entity_table: 'tenders',
    entity_id: tenderId,
  });
  if (error) fail(`/tenders/${tenderId}`, `Could not add the task: ${error.message}`);

  revalidatePath(`/tenders/${tenderId}`);
  redirect(`/tenders/${tenderId}`);
}

export async function completeTask(formData: FormData) {
  const id = String(formData.get('id') ?? '');
  const tenderId = String(formData.get('tender_id') ?? '');
  const supabase = createClient();
  const { error } = await supabase
    .from('tasks')
    .update({ status: 'done', completed_at: new Date().toISOString() })
    .eq('id', id);
  if (error) fail(`/tenders/${tenderId}`, `Could not update the task: ${error.message}`);

  revalidatePath(`/tenders/${tenderId}`);
  redirect(`/tenders/${tenderId}`);
}

export async function uploadDocument(formData: FormData) {
  const tenderId = String(formData.get('tender_id') ?? '');
  const file = formData.get('file') as File | null;
  const docType = String(formData.get('doc_type') ?? 'tender_document');
  const classification = String(formData.get('classification') ?? 'internal');

  if (!file || file.size === 0) fail(`/tenders/${tenderId}`, 'Choose a file to upload.');
  if (file!.size > 10 * 1024 * 1024) fail(`/tenders/${tenderId}`, 'File is larger than 10 MB.');

  const supabase = createClient();
  const bucket = process.env.SUPABASE_DOCUMENTS_BUCKET || 'documents';
  const safeName = file!.name.replace(/[^a-zA-Z0-9._-]/g, '_');
  const storagePath = `${tenderId}/${Date.now()}_${safeName}`;

  const upload = await supabase.storage.from(bucket).upload(storagePath, file!, {
    upsert: false,
    contentType: file!.type || 'application/octet-stream',
  });
  if (upload.error) fail(`/tenders/${tenderId}`, `Upload failed: ${upload.error.message}`);

  const { data: doc, error: docError } = await supabase
    .from('documents')
    .insert({
      file_name: file!.name,
      storage_bucket: bucket,
      storage_path: storagePath,
      mime_type: file!.type || null,
      size_bytes: file!.size,
      classification,
      entity_table: 'tenders',
      entity_id: tenderId,
    })
    .select('id')
    .single();
  if (docError) fail(`/tenders/${tenderId}`, `Could not record the document: ${docError.message}`);

  const { error: linkError } = await supabase
    .from('tender_documents')
    .insert({ tender_id: tenderId, document_id: doc!.id, doc_type: docType });
  if (linkError) fail(`/tenders/${tenderId}`, `Could not link the document: ${linkError.message}`);

  revalidatePath(`/tenders/${tenderId}`);
  redirect(`/tenders/${tenderId}`);
}
