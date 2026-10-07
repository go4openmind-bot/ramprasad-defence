import { PDFDocument, StandardFonts, rgb } from 'pdf-lib';
import { complianceLabel, complianceRollup } from './quotation';

export interface PdfQuotation {
  quotation_no: string;
  version: number;
  status: string;
  quote_date: string;
  validity_date: string | null;
  customer_name: string;
  tender_no: string | null;
  payment_terms: string | null;
  delivery_terms: string | null;
  warranty: string | null;
  notes: string | null;
  currency: string;
  subtotal: number;
  tax_total: number;
  grand_total: number;
  total_purchase_cost: number;
  total_logistics_cost: number;
  total_other_cost: number;
  total_margin: number;
}

export interface PdfItem {
  line_no: number;
  description: string;
  quantity: number;
  unit: string;
  line_cost: number;
  unit_price: number;
  tax_pct: number;
  line_total: number;
  line_margin: number;
  technical_compliance: string;
}

const A4 = { width: 595.28, height: 841.89 };
const MARGIN = 40;
const INK = rgb(0.11, 0.14, 0.19);
const MUTED = rgb(0.42, 0.46, 0.51);
const LINE = rgb(0.8, 0.83, 0.87);

function money(v: number | null | undefined, currency = 'INR'): string {
  const n = Number(v ?? 0);
  return `${currency} ${n.toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}

/** Build the quotation PDF. Pure function of the data — easy to test. */
export async function buildQuotationPdf(
  quotation: PdfQuotation,
  items: PdfItem[],
): Promise<Uint8Array> {
  const pdf = await PDFDocument.create();
  const font = await pdf.embedFont(StandardFonts.Helvetica);
  const bold = await pdf.embedFont(StandardFonts.HelveticaBold);

  const page = pdf.addPage([A4.width, A4.height]);
  let y = A4.height - MARGIN;

  const text = (
    s: string,
    x: number,
    yy: number,
    opts: { size?: number; useBold?: boolean; color?: typeof INK } = {},
  ) => {
    page.drawText(s, {
      x,
      y: yy,
      size: opts.size ?? 9,
      font: opts.useBold ? bold : font,
      color: opts.color ?? INK,
    });
  };

  text('RAMPRASAD DEFENCE', MARGIN, y, { size: 16, useBold: true });
  y -= 16;
  text('Defence Contract & Supply', MARGIN, y, { size: 9, color: MUTED });
  y -= 24;

  text(`QUOTATION ${quotation.quotation_no}  (v${quotation.version})`, MARGIN, y, { size: 13, useBold: true });
  y -= 16;
  text(`Status: ${quotation.status}`, MARGIN, y, { size: 9 });
  text(`Quote date: ${quotation.quote_date}`, 300, y, { size: 9 });
  y -= 12;
  text(`Customer: ${quotation.customer_name}`, MARGIN, y, { size: 9 });
  y -= 12;
  text(`Tender: ${quotation.tender_no ?? '—'}`, MARGIN, y, { size: 9 });
  text(`Valid until: ${quotation.validity_date ?? '—'}`, 300, y, { size: 9 });
  y -= 12;
  text(`Payment terms: ${quotation.payment_terms ?? '—'}`, MARGIN, y, { size: 9 });
  y -= 12;
  text(`Delivery terms: ${quotation.delivery_terms ?? '—'}`, MARGIN, y, { size: 9 });
  y -= 12;
  text(`Warranty: ${quotation.warranty ?? '—'}`, MARGIN, y, { size: 9 });
  y -= 8;

  page.drawLine({ start: { x: MARGIN, y }, end: { x: A4.width - MARGIN, y }, thickness: 1, color: LINE });
  y -= 16;

  const cols = { no: MARGIN, desc: MARGIN + 22, qty: 250, purch: 300, sell: 360, gst: 410, total: 445, margin: 520 };

  text('#', cols.no, y, { size: 8, useBold: true });
  text('Description', cols.desc, y, { size: 8, useBold: true });
  text('Qty', cols.qty, y, { size: 8, useBold: true });
  text('Cost', cols.purch, y, { size: 8, useBold: true });
  text('Sell', cols.sell, y, { size: 8, useBold: true });
  text('GST%', cols.gst, y, { size: 8, useBold: true });
  text('Line total', cols.total, y, { size: 8, useBold: true });
  text('Margin', cols.margin, y, { size: 8, useBold: true });
  y -= 6;
  page.drawLine({ start: { x: MARGIN, y }, end: { x: A4.width - MARGIN, y }, thickness: 0.5, color: LINE });
  y -= 12;

  for (const it of items) {
    if (y < 100) break;
    const desc = it.description.length > 42 ? `${it.description.slice(0, 41)}…` : it.description;
    text(String(it.line_no), cols.no, y, { size: 8 });
    text(desc, cols.desc, y, { size: 8 });
    text(`${it.quantity} ${it.unit}`, cols.qty, y, { size: 8 });
    text(money(it.line_cost), cols.purch, y, { size: 8 });
    text(money(it.unit_price), cols.sell, y, { size: 8 });
    text(String(it.tax_pct), cols.gst, y, { size: 8 });
    text(money(it.line_total), cols.total, y, { size: 8 });
    text(money(it.line_margin), cols.margin, y, { size: 8 });
    y -= 12;
  }

  y -= 6;
  page.drawLine({ start: { x: MARGIN, y }, end: { x: A4.width - MARGIN, y }, thickness: 0.5, color: LINE });
  y -= 16;

  const totalsX = 330;
  text('Net (ex-tax):', totalsX, y, { size: 9 });
  text(money(quotation.subtotal, quotation.currency), totalsX + 120, y, { size: 9 });
  y -= 12;
  text('GST:', totalsX, y, { size: 9 });
  text(money(quotation.tax_total, quotation.currency), totalsX + 120, y, { size: 9 });
  y -= 12;
  text('Grand total:', totalsX, y, { size: 10, useBold: true });
  text(money(quotation.grand_total, quotation.currency), totalsX + 120, y, { size: 10, useBold: true });
  y -= 16;
  text('Total cost:', totalsX, y, { size: 9 });
  text(
    money(quotation.total_purchase_cost + quotation.total_logistics_cost + quotation.total_other_cost, quotation.currency),
    totalsX + 120,
    y,
    { size: 9 },
  );
  y -= 12;
  text('Total margin:', totalsX, y, { size: 9 });
  text(money(quotation.total_margin, quotation.currency), totalsX + 120, y, { size: 9 });
  y -= 20;

  text(`Overall technical compliance: ${complianceLabel(complianceRollup(items))}`, MARGIN, y, {
    size: 8,
    color: MUTED,
  });
  y -= 24;

  if (quotation.notes) {
    text('Notes / T&C:', MARGIN, y, { size: 8, useBold: true });
    y -= 12;
    const words = quotation.notes.split(/\s+/);
    let line = '';
    for (const w of words) {
      if ((line + ' ' + w).trim().length > 95) {
        text(line.trim(), MARGIN, y, { size: 8, color: MUTED });
        y -= 11;
        line = w;
      } else {
        line += ' ' + w;
      }
    }
    if (line.trim()) text(line.trim(), MARGIN, y, { size: 8, color: MUTED });
  }

  return pdf.save();
}
