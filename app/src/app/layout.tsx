import type { Metadata } from 'next';
import Link from 'next/link';
import './globals.css';
import { isSupabaseConfigured } from '@/lib/supabase/env';
import { getCurrentUser } from '@/lib/supabase/server';
import { signOut } from './login/actions';

export const metadata: Metadata = {
  title: 'Ramprasad Defence — Tender Management',
  description: 'Tender management for defence contracts and supply.',
};

export default async function RootLayout({ children }: { children: React.ReactNode }) {
  let email: string | null = null;
  if (isSupabaseConfigured()) {
    try {
      const user = await getCurrentUser();
      email = user?.email ?? null;
    } catch {
      email = null;
    }
  }

  return (
    <html lang="en">
      <body>
        <header className="topbar">
          <div className="container">
            <div>
              <Link href="/tenders">Ramprasad Defence</Link>
              <span className="sub">Tender Management</span>
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 12, flexWrap: 'wrap' }}>
              <nav style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
                <Link href="/dashboard">Dashboard</Link>
                <span className="sub">|</span>
                <Link href="/tenders">All tenders</Link>
                <span className="sub">|</span>
                <Link href="/quotations">Quotations</Link>
                <span className="sub">|</span>
                <Link href="/procurement">Procurement</Link>
                <span className="sub">|</span>
                <Link href="/masters/customers">Masters</Link>
                <span className="sub">|</span>
                <Link href="/tenders/new">New tender</Link>
              </nav>
              {email ? (
                <form action={signOut} style={{ display: 'flex', alignItems: 'center', gap: 8, margin: 0 }}>
                  <span className="sub">{email}</span>
                  <button className="btn small ghost" type="submit">
                    Sign out
                  </button>
                </form>
              ) : (
                <Link href="/login">Sign in</Link>
              )}
            </div>
          </div>
        </header>
        <main className="container">{children}</main>
      </body>
    </html>
  );
}
