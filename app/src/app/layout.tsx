import type { Metadata } from 'next';
import Link from 'next/link';
import './globals.css';

export const metadata: Metadata = {
  title: 'Ramprasad Defence — Tender Management',
  description: 'Tender management for defence contracts and supply.',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>
        <header className="topbar">
          <div className="container">
            <div>
              <Link href="/tenders">Ramprasad Defence</Link>
              <span className="sub">Tender Management</span>
            </div>
            <div>
              <Link href="/dashboard">Dashboard</Link>
              <span className="sub"> | </span>
              <Link href="/tenders">All tenders</Link>
              <span className="sub"> | </span>
              <Link href="/quotations">Quotations</Link>
              <span className="sub"> | </span>
              <Link href="/procurement">Procurement</Link>
              <span className="sub"> | </span>
              <Link href="/masters/customers">Masters</Link>
              <span className="sub"> | </span>
              <Link href="/tenders/new">New tender</Link>
            </div>
          </div>
        </header>
        <main className="container">{children}</main>
      </body>
    </html>
  );
}
