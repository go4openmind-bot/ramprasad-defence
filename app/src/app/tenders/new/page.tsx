import Link from 'next/link';
import { TenderForm } from '@/components/TenderForm';
import { listCustomers, getUserDirectory } from '@/lib/data';

export const dynamic = 'force-dynamic';

export default async function NewTenderPage({
  searchParams,
}: {
  searchParams: { error?: string };
}) {
  const [customers, users] = await Promise.all([listCustomers(), getUserDirectory()]);

  return (
    <>
      <h1>New tender</h1>
      <p className="subtitle">
        Fields marked * are required. The system refuses to save a tender without them.
      </p>
      {searchParams.error && <div className="alert error">{searchParams.error}</div>}

      {customers.length === 0 ? (
        <div className="alert info">
          No customers exist yet. Add a customer before creating a tender. (Customer master is a
          later module; for now this is expected if the database is empty.)
        </div>
      ) : (
        <TenderForm mode="create" customers={customers} users={users} />
      )}

      <p>
        <Link href="/tenders">← Back to tenders</Link>
      </p>
    </>
  );
}
