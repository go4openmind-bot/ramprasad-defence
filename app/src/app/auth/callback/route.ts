import { NextResponse, type NextRequest } from 'next/server';
import { createClient } from '@/lib/supabase/server';

export const dynamic = 'force-dynamic';

/**
 * Auth callback for email links (password reset). Exchanges the one-time code
 * for a session cookie, then sends the user to the reset-password page.
 */
export async function GET(request: NextRequest) {
  const url = new URL(request.url);
  const code = url.searchParams.get('code');
  const errorDescription = url.searchParams.get('error_description');

  if (errorDescription) {
    return NextResponse.redirect(
      new URL('/forgot-password?error=' + encodeURIComponent(errorDescription), url.origin),
    );
  }

  if (code) {
    const supabase = createClient();
    const { error } = await supabase.auth.exchangeCodeForSession(code);
    if (error) {
      return NextResponse.redirect(
        new URL('/forgot-password?error=' + encodeURIComponent(error.message), url.origin),
      );
    }
  }

  return NextResponse.redirect(new URL('/reset-password', url.origin));
}
