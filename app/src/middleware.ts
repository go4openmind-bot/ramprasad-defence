import { createServerClient } from '@supabase/ssr';
import { NextResponse, type NextRequest } from 'next/server';
import { getSupabaseEnv, isSupabaseConfigured } from './lib/supabase/env';

/**
 * Refreshes the Supabase session and protects the application routes.
 * If a user is not signed in they are sent to /login.
 *
 * This middleware must NEVER break routing: any configuration or network
 * problem falls back to rendering the page. Data access is still protected by
 * Row Level Security in the database, which is the real guard.
 */
export async function middleware(request: NextRequest) {
  let response = NextResponse.next({ request });

  try {
    if (!isSupabaseConfigured()) return response;

    const { url, publishableKey } = getSupabaseEnv();

    const supabase = createServerClient(url, publishableKey, {
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value));
          response = NextResponse.next({ request });
          cookiesToSet.forEach(({ name, value, options }) => response.cookies.set(name, value, options));
        },
      },
    });

    const {
      data: { user },
    } = await supabase.auth.getUser();

    if (
      !user &&
      (request.nextUrl.pathname.startsWith('/tenders') ||
        request.nextUrl.pathname.startsWith('/quotations') ||
        request.nextUrl.pathname.startsWith('/procurement') ||
        request.nextUrl.pathname.startsWith('/dashboard') ||
        request.nextUrl.pathname.startsWith('/masters'))
    ) {
      const redirectUrl = request.nextUrl.clone();
      redirectUrl.pathname = '/login';
      redirectUrl.searchParams.set('next', request.nextUrl.pathname);
      return NextResponse.redirect(redirectUrl);
    }

    return response;
  } catch {
    // Never let an auth/config problem take the whole site down.
    return NextResponse.next({ request });
  }
}

export const config = {
  matcher: ['/tenders/:path*', '/quotations/:path*', '/procurement/:path*', '/dashboard/:path*', '/masters/:path*'],
};
