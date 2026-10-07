import Link from 'next/link';
import { QuotationForm } from '@/components/QuotationForm';
import { getQuotation, listCustomers, listTenderOptions } from '@/lib/data';
import { isFrozen } from '@/lib/quotation';

export const dynamic = 'force-dynamic';

export default async function EditQuotationPage({
  params,
  searchParams,
}: {
  params: { id: string };
  searchParams: { error?: string };
}) {
  const [quotation, customers, tenders] = await Promise.all([
    getQuotation(params.id),
    listCustomers(),
    listTenderOptions(),
  ]);

  if (!quotation) {
    return (
      <>
        <h1>Quotation not found</h1>
        <Link href="/quotations">← Back to quotations</Link>
      </>
    );
  }

  if (isFrozen(quotation.status)) {
    return (
      <>
        <h1>This quotation cannot be edited</h1>
        <div className="alert info">
          Quotation {quotation.quotation_no} v{quotation.version} is <strong>{quotation.status}</strong>.
          An approved quotation is never overwritten. Create a revision instead.
        </div>
        <div className="row tight">
          <Link className="btn" href={`/quotations/${quotation.id}`}>
            Back to quotation
          </Link>
        </div>
      </>
    );
  }

  return (
    <>
      <h1>Edit {quotation.quotation_no} v{quotation.version}</h1>
      <QuotationForm
        mode="edit"
        quotation={quotation}
        customers={customers}
        tenders={tenders}
        error={searchParams.error}
      />
    </>
  );
}
