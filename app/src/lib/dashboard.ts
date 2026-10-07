/**
 * Management dashboard: 16 metrics, each with a drill-down to the underlying
 * records. Every query runs through the signed-in user's session, so Row Level
 * Security still decides what a user may actually read.
 */
import { createClient } from './supabase/server';
import { deliveryRisk } from './procurement';
import { formatDate, formatMoney } from './format';

export const DASHBOARD_METRICS = [
  { key: 'active_tenders', label: 'Active tenders' },
  { key: 'tenders_closing_soon', label: 'Tenders closing soon' },
  { key: 'submitted_tenders', label: 'Submitted tenders' },
  { key: 'won_tenders', label: 'Won tenders' },
  { key: 'lost_tenders', label: 'Lost tenders' },
  { key: 'active_orders', label: 'Active customer orders' },
  { key: 'orders_at_risk', label: 'Orders at delivery risk' },
  { key: 'delayed_orders', label: 'Delayed orders' },
  { key: 'pending_oem_deliveries', label: 'Pending OEM deliveries' },
  { key: 'pending_pdi', label: 'Pending PDI' },
  { key: 'pending_dispatch', label: 'Pending dispatch' },
  { key: 'outstanding_payments', label: 'Outstanding payments' },
  { key: 'overdue_payments', label: 'Overdue payments' },
  { key: 'monthly_sales', label: 'Monthly sales' },
  { key: 'gross_margin', label: 'Gross margin' },
  { key: 'oem_performance', label: 'OEM performance' },
] as const;

export type MetricKey = (typeof DASHBOARD_METRICS)[number]['key'];

export interface Tile {
  key: MetricKey;
  label: string;
  count: number;
  value?: string;
  note?: string;
  color?: 'red' | 'yellow' | 'green' | 'grey';
}

export interface DrillColumn {
  key: string;
  label: string;
}

export interface DrillRow {
  cells: Record<string, string | null>;
  href?: string;
}

export interface DrillResult {
  title: string;
  subtitle?: string;
  columns: DrillColumn[];
  rows: DrillRow[];
  /** Summary values shown above the table. */
  summary?: { label: string; value: string }[];
}

const TERMINAL_TENDERS = ['won', 'lost', 'cancelled'];
const ACTIVE_ORDER_STATUSES = ['received', 'confirmed', 'in_procurement', 'partially_delivered', 'delivered', 'invoiced'];

function today(): string {
  return new Date().toISOString().slice(0, 10);
}

function addDays(date: string, days: number): string {
  const d = new Date(`${date}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}

function sum(values: number[]): number {
  return values.reduce((a, b) => a + Number(b || 0), 0);
}

// ===========================================================================
// Row loaders (reused by both the tiles and the drill-down pages)
// ===========================================================================

async function tenderRows(filter: { statusIn?: string[]; statusNotIn?: string[]; dueFrom?: string; dueTo?: string }) {
  const supabase = createClient();
  let query = supabase
    .from('tenders')
    .select('id, tender_no, title, status, priority, bid_due_date, customer:customers(name)')
    .order('bid_due_date', { ascending: true, nullsFirst: false })
    .limit(500);
  if (filter.statusIn) query = query.in('status', filter.statusIn);
  if (filter.statusNotIn) query = query.not('status', 'in', `(${filter.statusNotIn.join(',')})`);
  if (filter.dueFrom) query = query.gte('bid_due_date', filter.dueFrom);
  if (filter.dueTo) query = query.lte('bid_due_date', filter.dueTo);
  const { data, error } = await query;
  if (error) throw new Error(error.message);
  return (data ?? []).map((r: any) => ({ ...r, customer_name: r.customer?.name ?? '—' }));
}

async function orderRows() {
  const supabase = createClient();
  const { data, error } = await supabase
    .from('customer_orders')
    .select('id, order_no, order_date, status, grand_total, currency, customer:customers(name)')
    .order('order_date', { ascending: false })
    .limit(500);
  if (error) throw new Error(error.message);
  return (data ?? []).map((r: any) => ({ ...r, customer_name: r.customer?.name ?? '—' }));
}

async function poRows() {
  const supabase = createClient();
  const { data, error } = await supabase
    .from('purchase_orders')
    .select('id, po_no, status, grand_total, currency, expected_delivery_date, actual_delivery_date, oem:oems(name), requirement:material_requirements(required_by_date)')
    .order('expected_delivery_date', { ascending: true, nullsFirst: false })
    .limit(500);
  if (error) throw new Error(error.message);
  return (data ?? []).map((r: any) => {
    const risk = deliveryRisk({
      expectedDate: r.expected_delivery_date,
      requiredDate: r.requirement?.required_by_date ?? null,
      receivedDate: r.actual_delivery_date,
    });
    return {
      ...r,
      oem_name: r.oem?.name ?? '—',
      required_by_date: r.requirement?.required_by_date ?? null,
      risk,
    };
  });
}

async function receiptRows() {
  const supabase = createClient();
  const { data, error } = await supabase
    .from('material_receipts')
    .select('id, grn_no, received_date, status, inspection_status, purchase_order:purchase_orders(po_no), oem:oems(name)')
    .in('inspection_status', ['pending', 'in_progress'])
    .order('received_date', { ascending: true, nullsFirst: false })
    .limit(500);
  if (error) throw new Error(error.message);
  return (data ?? []).map((r: any) => ({
    ...r,
    po_no: r.purchase_order?.po_no ?? '—',
    oem_name: r.oem?.name ?? '—',
  }));
}

async function pendingDispatchRows() {
  const supabase = createClient();
  const { data, error } = await supabase
    .from('order_items')
    .select('id, line_no, description, quantity, delivered_qty, status, customer_order:customer_orders(order_no, status), product:products(name)')
    .limit(1000);
  if (error) throw new Error(error.message);
  return (data ?? [])
    .filter((r: any) => Number(r.delivered_qty) < Number(r.quantity))
    .filter((r: any) => !['closed', 'cancelled'].includes(r.customer_order?.status))
    .map((r: any) => ({
      ...r,
      order_no: r.customer_order?.order_no ?? '—',
      product_name: r.product?.name ?? null,
      customer_order_id: null,
    }));
}

interface InvoiceWithBalance {
  id: string;
  invoice_no: string;
  customer_name: string;
  due_date: string | null;
  status: string;
  grand_total: number;
  currency: string;
  paid: number;
  balance: number;
}

async function invoiceRows(): Promise<InvoiceWithBalance[]> {
  const supabase = createClient();
  const { data: invoices, error } = await supabase
    .from('invoices')
    .select('id, invoice_no, due_date, status, grand_total, currency, customer:customers(name)')
    .order('due_date', { ascending: true, nullsFirst: false })
    .limit(500);
  if (error) throw new Error(error.message);

  const { data: payments, error: payError } = await supabase
    .from('payments')
    .select('invoice_id, amount, payment_type')
    .eq('payment_type', 'customer_receipt');
  if (payError) throw new Error(payError.message);

  const paidByInvoice = new Map<string, number>();
  for (const p of payments ?? []) {
    if (!p.invoice_id) continue;
    paidByInvoice.set(p.invoice_id, (paidByInvoice.get(p.invoice_id) ?? 0) + Number(p.amount));
  }

  return (invoices ?? []).map((i: any) => {
    const paid = paidByInvoice.get(i.id) ?? 0;
    return {
      id: i.id,
      invoice_no: i.invoice_no,
      customer_name: i.customer?.name ?? '—',
      due_date: i.due_date,
      status: i.status,
      grand_total: Number(i.grand_total),
      currency: i.currency,
      paid,
      balance: Number(i.grand_total) - paid,
    };
  });
}

async function quotationMarginRows() {
  const supabase = createClient();
  const { data, error } = await supabase
    .from('quotations')
    .select('id, quotation_no, version, status, subtotal, total_margin, currency, customer:customers(name)')
    .in('status', ['approved', 'submitted', 'won'])
    .order('quote_date', { ascending: false })
    .limit(500);
  if (error) throw new Error(error.message);
  return (data ?? []).map((r: any) => ({ ...r, customer_name: r.customer?.name ?? '—' }));
}

export function monthlySales(orders: { order_date: string; grand_total: number }[]) {
  const byMonth = new Map<string, { month: string; orders: number; value: number }>();
  for (const o of orders) {
    const month = (o.order_date ?? '').slice(0, 7);
    if (!month) continue;
    const e = byMonth.get(month) ?? { month, orders: 0, value: 0 };
    e.orders += 1;
    e.value += Number(o.grand_total);
    byMonth.set(month, e);
  }
  return Array.from(byMonth.values()).sort((a, b) => (a.month < b.month ? 1 : -1)).slice(0, 12);
}

export interface OemPerformanceInput {
  oem_name: string;
  grand_total: number;
  actual_delivery_date: string | null;
  risk: { color: string };
}

export function oemPerformance(rows: OemPerformanceInput[]) {
  const byOem = new Map<string, { oem: string; orders: number; onTime: number; late: number; pending: number; atRisk: number; value: number }>();
  for (const po of rows) {
    const e = byOem.get(po.oem_name) ?? { oem: po.oem_name, orders: 0, onTime: 0, late: 0, pending: 0, atRisk: 0, value: 0 };
    e.orders += 1;
    e.value += Number(po.grand_total);
    if (po.actual_delivery_date) {
      if (po.risk.color === 'red') e.late += 1;
      else e.onTime += 1;
    } else {
      e.pending += 1;
      if (po.risk.color === 'red') e.atRisk += 1;
    }
    byOem.set(po.oem_name, e);
  }
  return Array.from(byOem.values()).sort((a, b) => b.late + b.atRisk - (a.late + a.atRisk));
}

// ===========================================================================
// Drill-downs
// ===========================================================================

/** Only management and administrators may view the management dashboard. */
export function canViewDashboard(roles: string[]): boolean {
  return roles.includes('admin') || roles.includes('management');
}

export async function loadDrill(key: string): Promise<DrillResult | null> {
  const t = today();

  switch (key) {
    case 'active_tenders': {
      const rows = await tenderRows({ statusNotIn: TERMINAL_TENDERS });
      return {
        title: 'Active tenders',
        subtitle: 'Tenders not yet won, lost or cancelled.',
        columns: tenderCols(),
        rows: rows.map((r) => ({ cells: tenderCells(r), href: `/tenders/${r.id}` })),
      };
    }
    case 'tenders_closing_soon': {
      const rows = await tenderRows({ statusNotIn: TERMINAL_TENDERS, dueFrom: t, dueTo: addDays(t, 7) });
      return {
        title: 'Tenders closing soon',
        subtitle: 'Bid due within the next 7 days.',
        columns: tenderCols(),
        rows: rows.map((r) => ({ cells: tenderCells(r), href: `/tenders/${r.id}` })),
      };
    }
    case 'submitted_tenders': {
      const rows = await tenderRows({ statusIn: ['submitted'] });
      return { title: 'Submitted tenders', columns: tenderCols(), rows: rows.map((r) => ({ cells: tenderCells(r), href: `/tenders/${r.id}` })) };
    }
    case 'won_tenders': {
      const rows = await tenderRows({ statusIn: ['won'] });
      return { title: 'Won tenders', columns: tenderCols(), rows: rows.map((r) => ({ cells: tenderCells(r), href: `/tenders/${r.id}` })) };
    }
    case 'lost_tenders': {
      const rows = await tenderRows({ statusIn: ['lost'] });
      return { title: 'Lost tenders', columns: tenderCols(), rows: rows.map((r) => ({ cells: tenderCells(r), href: `/tenders/${r.id}` })) };
    }
    case 'active_orders': {
      const rows = (await orderRows()).filter((o) => ACTIVE_ORDER_STATUSES.includes(o.status));
      return {
        title: 'Active customer orders',
        subtitle: 'Orders not closed or cancelled.',
        columns: orderCols(),
        rows: rows.map((r) => ({ cells: orderCells(r) })),
      };
    }
    case 'orders_at_risk': {
      const rows = (await poRows()).filter((p) => p.risk.color === 'red' || p.risk.color === 'yellow');
      return {
        title: 'Orders at delivery risk',
        subtitle: 'OEM purchase orders that may delay the customer delivery.',
        columns: poCols(),
        rows: rows.map((r) => ({ cells: poCells(r), href: `/procurement/orders/${r.id}` })),
      };
    }
    case 'delayed_orders': {
      const rows = (await poRows()).filter(
        (p) => !p.actual_delivery_date && p.expected_delivery_date && p.expected_delivery_date < t
          && !['cancelled', 'closed'].includes(p.status),
      );
      return {
        title: 'Delayed orders',
        subtitle: 'Purchase orders past their expected delivery date and not yet received.',
        columns: poCols(),
        rows: rows.map((r) => ({ cells: poCells(r), href: `/procurement/orders/${r.id}` })),
      };
    }
    case 'pending_oem_deliveries': {
      const rows = (await poRows()).filter((p) => ['approved', 'sent', 'partially_received'].includes(p.status));
      return {
        title: 'Pending OEM deliveries',
        columns: poCols(),
        rows: rows.map((r) => ({ cells: poCells(r), href: `/procurement/orders/${r.id}` })),
      };
    }
    case 'pending_pdi': {
      const rows = await receiptRows();
      return {
        title: 'Pending PDI',
        subtitle: 'Material received but inspection not yet passed.',
        columns: [
          { key: 'grn', label: 'GRN' },
          { key: 'po', label: 'PO' },
          { key: 'oem', label: 'OEM' },
          { key: 'received', label: 'Received' },
          { key: 'inspection', label: 'Inspection' },
        ],
        rows: rows.map((r) => ({
          cells: { grn: r.grn_no, po: r.po_no, oem: r.oem_name, received: formatDate(r.received_date), inspection: r.inspection_status },
        })),
      };
    }
    case 'pending_dispatch': {
      const rows = await pendingDispatchRows();
      return {
        title: 'Pending dispatch',
        subtitle: 'Order lines not yet fully dispatched on active orders.',
        columns: [
          { key: 'order', label: 'Customer order' },
          { key: 'line', label: 'Line' },
          { key: 'product', label: 'Product' },
          { key: 'ordered', label: 'Ordered' },
          { key: 'delivered', label: 'Dispatched' },
          { key: 'status', label: 'Status' },
        ],
        rows: rows.map((r) => ({
          cells: { order: r.order_no, line: String(r.line_no), product: r.product_name ?? r.description, ordered: String(r.quantity), delivered: String(r.delivered_qty), status: r.status },
        })),
      };
    }
    case 'outstanding_payments': {
      const rows = (await invoiceRows()).filter(
        (i) => ['issued', 'partially_paid', 'overdue'].includes(i.status) && i.balance > 0,
      );
      const total = sum(rows.map((r) => r.balance));
      return {
        title: 'Outstanding payments',
        subtitle: 'Invoices issued but not fully paid.',
        columns: invoiceCols(),
        rows: rows.map(invoiceRow),
        summary: [{ label: 'Total outstanding', value: formatMoney(total) }],
      };
    }
    case 'overdue_payments': {
      const rows = (await invoiceRows()).filter(
        (i) => ['issued', 'partially_paid', 'overdue'].includes(i.status) && i.balance > 0 && !!i.due_date && i.due_date < t,
      );
      const total = sum(rows.map((r) => r.balance));
      return {
        title: 'Overdue payments',
        subtitle: 'Outstanding invoices past their due date.',
        columns: invoiceCols(),
        rows: rows.map(invoiceRow),
        summary: [{ label: 'Total overdue', value: formatMoney(total) }],
      };
    }
    case 'monthly_sales': {
      const months = monthlySales(await orderRows());
      return {
        title: 'Monthly sales',
        subtitle: 'Customer order value by month (last 12).',
        columns: [
          { key: 'month', label: 'Month' },
          { key: 'orders', label: 'Orders' },
          { key: 'value', label: 'Order value' },
        ],
        rows: months.map((m) => ({ cells: { month: m.month, orders: String(m.orders), value: formatMoney(m.value) } })),
        summary: [{ label: 'This month', value: formatMoney(months[0]?.value ?? 0) }],
      };
    }
    case 'gross_margin': {
      const rows = await quotationMarginRows();
      const margin = sum(rows.map((r) => r.total_margin));
      const base = sum(rows.map((r) => r.subtotal));
      const pct = base > 0 ? Math.round((margin / base) * 10000) / 100 : 0;
      return {
        title: 'Gross margin',
        subtitle: 'Margin on approved, submitted and won quotations.',
        columns: [
          { key: 'quotation', label: 'Quotation' },
          { key: 'customer', label: 'Customer' },
          { key: 'status', label: 'Status' },
          { key: 'net', label: 'Net (ex-tax)' },
          { key: 'margin', label: 'Margin' },
        ],
        rows: rows.map((r) => ({
          cells: { quotation: `${r.quotation_no} v${r.version}`, customer: r.customer_name, status: r.status, net: formatMoney(r.subtotal, r.currency), margin: formatMoney(r.total_margin, r.currency) },
          href: `/quotations/${r.id}`,
        })),
        summary: [
          { label: 'Total margin', value: formatMoney(margin) },
          { label: 'Margin %', value: `${pct}%` },
        ],
      };
    }
    case 'oem_performance': {
      const rows = oemPerformance(await poRows());
      return {
        title: 'OEM performance',
        subtitle: 'Deliveries on time vs late, and current risk.',
        columns: [
          { key: 'oem', label: 'OEM' },
          { key: 'orders', label: 'Orders' },
          { key: 'onTime', label: 'On time' },
          { key: 'late', label: 'Late' },
          { key: 'pending', label: 'Pending' },
          { key: 'atRisk', label: 'At risk' },
          { key: 'value', label: 'Value' },
        ],
        rows: rows.map((r) => ({
          cells: { oem: r.oem, orders: String(r.orders), onTime: String(r.onTime), late: String(r.late), pending: String(r.pending), atRisk: String(r.atRisk), value: formatMoney(r.value) },
        })),
      };
    }
    default:
      return null;
  }
}

// --- shared column/cell helpers --------------------------------------------

function tenderCols(): DrillColumn[] {
  return [
    { key: 'tender', label: 'Tender' },
    { key: 'title', label: 'Title' },
    { key: 'customer', label: 'Customer' },
    { key: 'status', label: 'Status' },
    { key: 'due', label: 'Closing date' },
  ];
}
function tenderCells(r: any) {
  return { tender: r.tender_no, title: r.title, customer: r.customer_name, status: r.status, due: formatDate(r.bid_due_date) };
}

function orderCols(): DrillColumn[] {
  return [
    { key: 'order', label: 'Order' },
    { key: 'customer', label: 'Customer' },
    { key: 'date', label: 'Order date' },
    { key: 'status', label: 'Status' },
    { key: 'value', label: 'Value' },
  ];
}
function orderCells(r: any) {
  return { order: r.order_no, customer: r.customer_name, date: formatDate(r.order_date), status: r.status, value: formatMoney(r.grand_total, r.currency) };
}

function poCols(): DrillColumn[] {
  return [
    { key: 'po', label: 'PO' },
    { key: 'oem', label: 'OEM' },
    { key: 'status', label: 'Status' },
    { key: 'expected', label: 'Expected' },
    { key: 'actual', label: 'Actual' },
    { key: 'required', label: 'Required by' },
    { key: 'risk', label: 'Risk' },
  ];
}
function poCells(r: any) {
  return {
    po: r.po_no,
    oem: r.oem_name,
    status: r.status,
    expected: formatDate(r.expected_delivery_date),
    actual: formatDate(r.actual_delivery_date),
    required: formatDate(r.required_by_date),
    risk: r.risk?.label ?? '',
  };
}

function invoiceCols(): DrillColumn[] {
  return [
    { key: 'invoice', label: 'Invoice' },
    { key: 'customer', label: 'Customer' },
    { key: 'due', label: 'Due date' },
    { key: 'status', label: 'Status' },
    { key: 'total', label: 'Total' },
    { key: 'paid', label: 'Paid' },
    { key: 'balance', label: 'Balance' },
  ];
}
function invoiceRow(i: InvoiceWithBalance): DrillRow {
  return {
    cells: {
      invoice: i.invoice_no,
      customer: i.customer_name,
      due: formatDate(i.due_date),
      status: i.status,
      total: formatMoney(i.grand_total, i.currency),
      paid: formatMoney(i.paid, i.currency),
      balance: formatMoney(i.balance, i.currency),
    },
  };
}

// ===========================================================================
// Tiles
// ===========================================================================

export async function computeTiles(): Promise<Tile[]> {
  const t = today();
  const [
    activeTenders, closingSoon, submitted, won, lost,
    orders, pos, receipts, dispatch, invoices,
  ] = await Promise.all([
    tenderRows({ statusNotIn: TERMINAL_TENDERS }),
    tenderRows({ statusNotIn: TERMINAL_TENDERS, dueFrom: t, dueTo: addDays(t, 7) }),
    tenderRows({ statusIn: ['submitted'] }),
    tenderRows({ statusIn: ['won'] }),
    tenderRows({ statusIn: ['lost'] }),
    orderRows(),
    poRows(),
    receiptRows(),
    pendingDispatchRows(),
    invoiceRows(),
  ]);

  const activeOrders = orders.filter((o) => ACTIVE_ORDER_STATUSES.includes(o.status));
  const atRisk = pos.filter((p) => p.risk.color === 'red' || p.risk.color === 'yellow');
  const delayed = pos.filter(
    (p) => !p.actual_delivery_date && p.expected_delivery_date && p.expected_delivery_date < t && !['cancelled', 'closed'].includes(p.status),
  );
  const pendingDeliveries = pos.filter((p) => ['approved', 'sent', 'partially_received'].includes(p.status));
  const outstanding = invoices.filter((i) => ['issued', 'partially_paid', 'overdue'].includes(i.status) && i.balance > 0);
  const overdue = outstanding.filter((i) => !!i.due_date && i.due_date < t);
  const months = monthlySales(orders);
  const margins = await quotationMarginRows();
  const marginTotal = sum(margins.map((m) => m.total_margin));
  const marginBase = sum(margins.map((m) => m.subtotal));
  const marginPct = marginBase > 0 ? Math.round((marginTotal / marginBase) * 10000) / 100 : 0;
  const oem = oemPerformance(pos);
  const worstOem = oem.find((o) => o.late + o.atRisk > 0);

  return [
    { key: 'active_tenders', label: 'Active tenders', count: activeTenders.length },
    { key: 'tenders_closing_soon', label: 'Tenders closing soon', count: closingSoon.length, note: 'next 7 days', color: closingSoon.length ? 'yellow' : 'grey' },
    { key: 'submitted_tenders', label: 'Submitted tenders', count: submitted.length },
    { key: 'won_tenders', label: 'Won tenders', count: won.length, color: 'green' },
    { key: 'lost_tenders', label: 'Lost tenders', count: lost.length, color: 'grey' },
    { key: 'active_orders', label: 'Active customer orders', count: activeOrders.length },
    { key: 'orders_at_risk', label: 'Orders at delivery risk', count: atRisk.length, color: atRisk.some((p) => p.risk.color === 'red') ? 'red' : atRisk.length ? 'yellow' : 'grey' },
    { key: 'delayed_orders', label: 'Delayed orders', count: delayed.length, color: delayed.length ? 'red' : 'grey' },
    { key: 'pending_oem_deliveries', label: 'Pending OEM deliveries', count: pendingDeliveries.length },
    { key: 'pending_pdi', label: 'Pending PDI', count: receipts.length, color: receipts.length > 5 ? 'yellow' : 'grey' },
    { key: 'pending_dispatch', label: 'Pending dispatch', count: dispatch.length },
    { key: 'outstanding_payments', label: 'Outstanding payments', count: outstanding.length, value: formatMoney(sum(outstanding.map((i) => i.balance))) },
    { key: 'overdue_payments', label: 'Overdue payments', count: overdue.length, value: formatMoney(sum(overdue.map((i) => i.balance))), color: overdue.length ? 'red' : 'grey' },
    { key: 'monthly_sales', label: 'Monthly sales', count: months[0]?.orders ?? 0, value: formatMoney(months[0]?.value ?? 0), note: `this month (${months[0]?.month ?? '—'})` },
    { key: 'gross_margin', label: 'Gross margin', count: margins.length, value: formatMoney(marginTotal), note: `${marginPct}% of net` },
    { key: 'oem_performance', label: 'OEM performance', count: oem.length, note: worstOem ? `${worstOem.oem}: ${worstOem.late} late, ${worstOem.atRisk} at risk` : 'no issues' },
  ];
}
