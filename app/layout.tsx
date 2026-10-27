import type { Metadata, Viewport } from 'next';
import { cookies } from 'next/headers';
import { GeistSans } from 'geist/font/sans';
import { GeistMono } from 'geist/font/mono';
import { ServiceWorker } from '@/components/ServiceWorker';
import { getCurrentUser } from '@/lib/auth/currentUser';
import { resolveAppearance } from '@/lib/appearance';
import './globals.css';

export const metadata: Metadata = {
  title: 'daily-web',
  description: 'Painel pessoal do dia a dia',
  appleWebApp: {
    capable: true,
    title: 'daily',
    // O iOS não lê o manifest: a barra de status precisa ser dita aqui, ou
    // ela fica clara sobre o fundo escuro da app.
    statusBarStyle: 'black-translucent',
  },
  icons: {
    apple: '/icons/apple-touch-icon.png',
  },
};

export const viewport: Viewport = {
  // The one place a literal colour is unavoidable: this is a meta tag the browser
  // chrome reads, and a custom property cannot reach it. Both values are the
  // computed --mesh-base of their theme; change them when that token changes.
  themeColor: [
    { media: '(prefers-color-scheme: light)', color: '#f9fafd' },
    { media: '(prefers-color-scheme: dark)', color: '#08080a' },
  ],
  // A app é um painel, não um documento: dar zoom horizontal só quebraria as
  // colunas, mas o zoom de acessibilidade continua liberado.
  width: 'device-width',
  initialScale: 1,
  viewportFit: 'cover',
};

/**
 * Reading the cookies here, rather than stamping from a client effect or a blocking
 * inline script, is what prevents the wrong-theme flash on first paint. It costs
 * static rendering for the whole route tree — a cost this dashboard never paid
 * anyway, since every screen is authenticated and polled.
 */
export default async function RootLayout({ children }: { children: React.ReactNode }) {
  const jar = await cookies();
  const user = await getCurrentUser();
  const { theme, density, backdrop, width } = resolveAppearance(
    (name) => jar.get(name)?.value,
    user?.id ?? null,
  );
  const forced = theme === 'system' ? '' : theme;

  return (
    <html
      lang="pt-BR"
      // The client changes both after hydration.
      suppressHydrationWarning
      data-density={density === 'compact' ? 'compact' : undefined}
      data-backdrop={backdrop === 'mesh' ? undefined : backdrop}
      data-width={width === 'full' ? undefined : width}
      className={`${GeistSans.variable} ${GeistMono.variable} ${forced}`.trim()}
    >
      {/* No background utility here: body paints --mesh-base from globals.css,
          and a bg-* class would win over it and hide the page colour. */}
      <body className="min-h-screen text-foreground antialiased">
        <ServiceWorker />
        {children}
      </body>
    </html>
  );
}
