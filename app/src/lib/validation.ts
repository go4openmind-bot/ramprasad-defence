import { z } from 'zod';
import { TENDER_STATUS_CODES } from './tenderStatus';

/** Empty text becomes undefined; trimmed. */
const optionalText = z
  .string()
  .trim()
  .optional()
  .transform((v) => (v && v.length > 0 ? v : undefined));

const requiredText = (field: string) =>
  z.string({ required_error: `${field} is required` }).trim().min(1, `${field} is required`);

const optionalDate = z
  .string()
  .trim()
  .optional()
  .transform((v) => (v && v.length > 0 ? v : undefined))
  .refine((v) => v === undefined || /^\d{4}-\d{2}-\d{2}$/.test(v), 'Enter a valid date');

const optionalUuid = z
  .string()
  .trim()
  .optional()
  .transform((v) => (v && v.length > 0 ? v : undefined))
  .refine((v) => v === undefined || z.string().uuid().safeParse(v).success, 'Invalid selection');

const money = z
  .string()
  .trim()
  .optional()
  .transform((v) => (v && v.length > 0 ? Number(v) : undefined))
  .refine((v) => v === undefined || (Number.isFinite(v) && v >= 0), 'Enter a valid amount');

export const tenderSchema = z
  .object({
    tender_no: requiredText('Tender number'),
    customer_id: z.string({ required_error: 'Customer is required' }).uuid('Customer is required'),
    title: requiredText('Title'),
    description: optionalText,
    source: optionalText,
    category: optionalText,
    received_date: requiredText('Received date'),
    bid_due_date: optionalDate,
    emd_amount: money,
    currency: z.string().trim().default('INR'),
    priority: z.enum(['low', 'medium', 'high', 'critical']).default('medium'),
    status: z.enum(TENDER_STATUS_CODES as [string, ...string[]]).default('new'),
    owner_user_id: optionalUuid,
    notes: optionalText,
  })
  .refine(
    (v) => !v.bid_due_date || v.bid_due_date >= v.received_date,
    { message: 'Closing date cannot be before the received date', path: ['bid_due_date'] },
  );

export type TenderInput = z.infer<typeof tenderSchema>;

export const requirementSchema = z.object({
  description: requiredText('Description'),
  specification: optionalText,
  quantity: z
    .string()
    .trim()
    .min(1, 'Quantity is required')
    .transform((v) => Number(v))
    .refine((v) => Number.isFinite(v) && v > 0, 'Quantity must be greater than zero'),
  unit: z.string().trim().min(1).default('NO'),
});

export const noteSchema = z.object({
  note: requiredText('Note'),
});

export const taskSchema = z.object({
  title: requiredText('Task'),
  assigned_to: optionalUuid,
  due_date: optionalDate,
  priority: z.enum(['low', 'medium', 'high', 'critical']).default('medium'),
});

/** Turn a ZodError into { field: message } for redisplay. */
export function fieldErrors(error: z.ZodError): Record<string, string> {
  const out: Record<string, string> = {};
  for (const issue of error.issues) {
    const key = issue.path.join('.') || 'form';
    if (!out[key]) out[key] = issue.message;
  }
  return out;
}

// --- Quotations ------------------------------------------------------------

const numberField = (label: string, min = 0) =>
  z
    .string()
    .trim()
    .min(1, `${label} is required`)
    .transform((v) => Number(v))
    .refine((v) => Number.isFinite(v) && v >= min, `${label} must be a number of at least ${min}`);

const optionalNumber = z
  .string()
  .trim()
  .optional()
  .transform((v) => (v && v.length > 0 ? Number(v) : undefined))
  .refine((v) => v === undefined || Number.isFinite(v), 'Enter a valid number');

const percentField = (label: string) =>
  z
    .string()
    .trim()
    .optional()
    .transform((v) => (v && v.length > 0 ? Number(v) : 0))
    .refine((v) => v === undefined || (Number.isFinite(v) && v >= 0 && v <= 100), `${label} must be between 0 and 100`);

export const quotationSchema = z
  .object({
    customer_id: z.string({ required_error: 'Customer is required' }).uuid('Customer is required'),
    tender_id: optionalUuid,
    opportunity_id: optionalUuid,
    quote_date: requiredText('Quote date'),
    validity_date: optionalDate,
    currency: z.string().trim().default('INR'),
    payment_terms: optionalText,
    delivery_terms: optionalText,
    warranty: optionalText,
    notes: optionalText,
    status: z.string().trim().default('draft'),
  })
  .refine(
    (v) => !v.validity_date || v.validity_date >= v.quote_date,
    { message: 'Validity cannot be before the quote date', path: ['validity_date'] },
  );

export const quotationItemSchema = z.object({
  description: requiredText('Description'),
  quantity: numberField('Quantity', 0.001),
  unit: z.string().trim().min(1).default('NO'),
  unit_price: numberField('Selling price', 0),
  discount_pct: percentField('Discount'),
  tax_pct: percentField('GST'),
  purchase_unit_cost: numberField('Purchase cost', 0),
  logistics_unit_cost: optionalNumber,
  other_unit_cost: optionalNumber,
  product_id: optionalUuid,
  source_oem_id: optionalUuid,
  tender_requirement_id: optionalUuid,
  technical_compliance: z
    .enum(['pending', 'compliant', 'partially_compliant', 'non_compliant', 'not_applicable'])
    .default('pending'),
});

export const revisionSchema = z.object({
  quotation_id: z.string().uuid('Missing quotation'),
});

// --- Procurement -----------------------------------------------------------

export const materialRequirementSchema = z.object({
  requirement_no: optionalText,
  customer_order_id: optionalUuid,
  requested_by: optionalUuid,
  required_by_date: optionalDate,
  priority: z.enum(['low', 'medium', 'high', 'critical']).default('medium'),
  notes: optionalText,
});

export const materialRequirementItemSchema = z.object({
  description: requiredText('Description'),
  quantity: numberField('Quantity', 0.001),
  unit: z.string().trim().min(1).default('NO'),
  product_id: optionalUuid,
  required_by: optionalDate,
});

export const oemQuotationSchema = z.object({
  oem_rfq_id: z.string().uuid('Missing RFQ'),
  oem_id: z.string().uuid('Missing OEM'),
  quote_date: requiredText('Quote date'),
  validity_date: optionalDate,
  currency: z.string().trim().default('INR'),
  payment_terms: optionalText,
  delivery_terms: optionalText,
  warranty: optionalText,
  lead_time_days: optionalNumber,
  notes: optionalText,
});

export const oemQuotationItemSchema = z.object({
  description: requiredText('Description'),
  quantity: numberField('Quantity', 0.001),
  unit: z.string().trim().min(1).default('NO'),
  unit_price: numberField('Unit price', 0),
  tax_pct: percentField('GST'),
  product_id: optionalUuid,
});

export const expectedDeliverySchema = z.object({
  expected_delivery_date: requiredText('Expected delivery date'),
  payment_terms: optionalText,
  warranty: optionalText,
});

export const materialReceiptSchema = z.object({
  received_date: requiredText('Received date'),
  docket_no: optionalText,
  notes: optionalText,
});

export const pdiSchema = z.object({
  inspection_type: z.enum(['incoming', 'in_process', 'final', 'pdi', 'third_party', 'dgqa', 'dgaqa']).default('pdi'),
  result: z.enum(['pending', 'pass', 'fail', 'conditional']).default('pending'),
  certificate_no: optionalText,
  agency: optionalText,
  notes: optionalText,
});

export const procurementDocumentTypeSchema = z.enum([
  'compliance_certificate',
  'test_certificate',
  'iso_certificate',
  'gst_certificate',
  'pan',
  'warranty_certificate',
  'packing_list',
  'invoice',
  'other',
]);
