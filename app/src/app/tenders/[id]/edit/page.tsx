import Link from 'next/link';
import { TenderForm } from '@/components/TenderForm';
import { getTender, listCustomers, getUserDirectory } from '@/lib/data';

export const dynamic = 'force-dynamic';

export default async function EditTenderPage({
  params,
  searchParams,
}: {
  params: { id: string };
  searchParams: { error?: string };
}) {
  const [tender, customers, users] = await Promise.all([
    getTender(params.id),
    listCustomers(),
    getUserDirectory(),
  ]);

  if (!tender) {
    return (
      <>
        <h1>Tender not found</h1>
        <p className="subtitle">It may have been deleted, or you may not have access to it.</p>
        <Link href="/tenders">← Back to tenders</Link>
      </>
    );
  }

  return (
    <>
      <h1>Edit {tender.tender_no}</h1>
      <p className="subtitle">{tender.title}</p>
      <TenderForm mode="edit" tender={tender} customers={customers} users={users} error={searchParams.error} />
    </>
  );
}
