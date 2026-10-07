'use server';

import { redirect } from 'next/navigation';
import { revalidatePath } from 'next/cache';
import { createClient } from '@/lib/supabase/server';

function fail(path: string, message: string): never {
  const sep = path.includes('?') ? '&' : '?';
  redirect(`${path}${sep}error=${encodeURIComponent(message)}`);
}

const txt = (fd: FormData, k: string) => String(fd.get(k) ?? '').trim();
const opt = (fd: FormData, k: string) => txt(fd, k) || null;

export async function createCustomer(formData: FormData) {
  const code = txt(formData, 'code');
  const name = txt(formData, 'name');
  if (!code) fail('/masters/customers', 'Customer code is required.');
  if (!name) fail('/masters/customers', 'Customer name is required.');

  const supabase = createClient();
  const { error } = await supabase.from('customers').insert({
    code,
    name,
    customer_type: txt(formData, 'customer_type') || 'other',
    address_line1: opt(formData, 'address_line1'),
    city: opt(formData, 'city'),
    state: opt(formData, 'state'),
    pincode: opt(formData, 'pincode'),
    country: txt(formData, 'country') || 'India',
    gstin: opt(formData, 'gstin'),
    email: opt(formData, 'email'),
    phone: opt(formData, 'phone'),
    status: 'active',
  });
  if (error) fail('/masters/customers', `Could not add customer: ${error.message}`);

  revalidatePath('/masters/customers');
  revalidatePath('/quotations/new');
  redirect('/masters/customers?ok=1');
}

export async function createProduct(formData: FormData) {
  const code = txt(formData, 'code');
  const name = txt(formData, 'name');
  if (!code) fail('/masters/products', 'Product code is required.');
  if (!name) fail('/masters/products', 'Product name is required.');

  const supabase = createClient();
  const { error } = await supabase.from('products').insert({
    code,
    name,
    description: opt(formData, 'description'),
    category: opt(formData, 'category'),
    unit: txt(formData, 'unit') || 'NO',
    hsn_code: opt(formData, 'hsn_code'),
    manufacturer: opt(formData, 'manufacturer'),
    status: 'active',
  });
  if (error) fail('/masters/products', `Could not add product: ${error.message}`);

  revalidatePath('/masters/products');
  redirect('/masters/products?ok=1');
}

export async function createOem(formData: FormData) {
  const code = txt(formData, 'code');
  const name = txt(formData, 'name');
  if (!code) fail('/masters/oems', 'OEM code is required.');
  if (!name) fail('/masters/oems', 'OEM name is required.');

  const supabase = createClient();
  const { error } = await supabase.from('oems').insert({
    code,
    name,
    oem_type: opt(formData, 'oem_type'),
    city: opt(formData, 'city'),
    state: opt(formData, 'state'),
    country: txt(formData, 'country') || 'India',
    gstin: opt(formData, 'gstin'),
    email: opt(formData, 'email'),
    phone: opt(formData, 'phone'),
    payment_terms: opt(formData, 'payment_terms'),
    status: 'active',
  });
  if (error) fail('/masters/oems', `Could not add OEM: ${error.message}`);

  revalidatePath('/masters/oems');
  redirect('/masters/oems?ok=1');
}
