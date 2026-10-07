import { describe, expect, it } from 'vitest';
import {
  complianceRollup,
  isFrozen,
  marginPercent,
  parseQuotationStatus,
  quotationStatusLabel,
} from '../src/lib/quotation';
import { buildQuotationPdf, type PdfItem, type PdfQuotation } from '../src/lib/quotationPdf';

describe('quotation margin and compliance', () => {
  it('computes margin as a percentage of net selling', () => {
    expect(marginPercent(230, 130)).toBe(56.52);
    expect(marginPercent(0, 100)).toBeNull();
  });

  it('rolls technical compliance up to the worst line', () => {
    expect(complianceRollup([])).toBe('pending');
    expect(
      complianceRollup([{ technical_compliance: 'compliant' }, { technical_compliance: 'compliant' }]),
    ).toBe('compliant');
    expect(
      complianceRollup([
        { technical_compliance: 'compliant' },
        { technical_compliance: 'partially_compliant' },
        { technical_compliance: 'pending' },
      ]),
    ).toBe('partially_compliant');
    expect(
      complianceRollup([
        { technical_compliance: 'partially_compliant' },
        { technical_compliance: 'non_compliant' },
      ]),
    ).toBe('non_compliant');
  });
});

describe('quotation status and immutability', () => {
  it('freezes approved / submitted / won / lost quotations', () => {
    expect(isFrozen('approved')).toBe(true);
    expect(isFrozen('submitted')).toBe(true);
    expect(isFrozen('won')).toBe(true);
    expect(isFrozen('lost')).toBe(true);
    expect(isFrozen('draft')).toBe(false);
    expect(isFrozen('pending_approval')).toBe(false);
  });

  it('labels and normalises statuses', () => {
    expect(quotationStatusLabel('pending_approval')).toBe('Pending Approval');
    expect(parseQuotationStatus('bogus')).toBe('draft');
    expect(parseQuotationStatus('won')).toBe('won');
  });
});

describe('quotation PDF', () => {
  it('generates a real PDF document', async () => {
    const quotation: PdfQuotation = {
      quotation_no: 'QTN-0001',
      version: 1,
      status: 'draft',
      quote_date: '2026-10-07',
      validity_date: '2026-11-07',
      customer_name: 'Indian Army',
      tender_no: 'TENDER/2026/01',
      payment_terms: '30% advance, 70% on delivery',
      delivery_terms: '8-10 weeks, FOR destination',
      warranty: '24 months',
      notes: 'Prices inclusive of packing.',
      currency: 'INR',
      subtotal: 230,
      tax_total: 41.4,
      grand_total: 271.4,
      total_purchase_cost: 80,
      total_logistics_cost: 10,
      total_other_cost: 10,
      total_margin: 130,
    };
    const items: PdfItem[] = [
      {
        line_no: 1,
        description: 'Radio Set',
        quantity: 2,
        unit: 'NO',
        line_cost: 100,
        unit_price: 100,
        tax_pct: 18,
        line_total: 212.4,
        line_margin: 80,
        technical_compliance: 'compliant',
      },
    ];

    const bytes = await buildQuotationPdf(quotation, items);
    const head = String.fromCharCode(bytes[0], bytes[1], bytes[2], bytes[3]);
    expect(head).toBe('%PDF');
    expect(bytes.length).toBeGreaterThan(800);
  });
});
