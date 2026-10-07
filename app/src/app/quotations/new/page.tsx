import { QuotationForm } from '@/components/QuotationForm';
import { listCustomers, listTenderOptions } from '@/lib/data';

export const dynamic = 'force-dynamic';

export default async function NewQuotationPage({
  searchParams,
}: {
  searchParams: { error?: string; tender_id?: string; customer_id?: string };
}) {
  const [customers, tenders] = await Promise.all([listCustomers(), listTenderOptions()]);

  return (
    <>
      <h1>New quotation</h1>
      <p className="subtitle">
        Link the quotation to a customer and (optionally) a tender, then add product lines with cost,
        margin and selling price on the next screen.
      </p>

      {customers.length === 0 ? (
        <div className="alert info">Add a customer first — a quotation must belong to a customer.</div>
      ) : (
        <QuotationForm
          mode="create"
          customers={customers}
          tenders={tenders}
          error={searchParams.error}
          defaultTenderId={searchParams.tender_id}
          defaultCustomerId={searchParams.customer_id}
        />
      )}
    </>
  );
}
