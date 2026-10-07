import { getQuotation, getQuotationItems } from '@/lib/data';
import { buildQuotationPdf } from '@/lib/quotationPdf';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET(_request: Request, { params }: { params: { id: string } }) {
  const quotation = await getQuotation(params.id);
  if (!quotation) {
    return new Response('Quotation not found', { status: 404 });
  }
  const items = await getQuotationItems(params.id);

  const bytes = await buildQuotationPdf(
    {
      quotation_no: quotation.quotation_no,
      version: quotation.version,
      status: quotation.status,
      quote_date: quotation.quote_date,
      validity_date: quotation.validity_date,
      customer_name: quotation.customer_name,
      tender_no: quotation.tender_no,
      payment_terms: quotation.payment_terms,
      delivery_terms: quotation.delivery_terms,
      warranty: quotation.warranty,
      notes: quotation.notes,
      currency: quotation.currency,
      subtotal: quotation.subtotal,
      tax_total: quotation.tax_total,
      grand_total: quotation.grand_total,
      total_purchase_cost: quotation.total_purchase_cost,
      total_logistics_cost: quotation.total_logistics_cost,
      total_other_cost: quotation.total_other_cost,
      total_margin: quotation.total_margin,
    },
    items.map((i) => ({
      line_no: i.line_no,
      description: i.description,
      quantity: i.quantity,
      unit: i.unit,
      line_cost: i.line_cost,
      unit_price: i.unit_price,
      tax_pct: i.tax_pct,
      line_total: i.line_total,
      line_margin: i.line_margin,
      technical_compliance: i.technical_compliance,
    })),
  );

  return new Response(Buffer.from(bytes), {
    headers: {
      'Content-Type': 'application/pdf',
      'Content-Disposition': `attachment; filename="${quotation.quotation_no}-v${quotation.version}.pdf"`,
      'Cache-Control': 'no-store',
    },
  });
}
