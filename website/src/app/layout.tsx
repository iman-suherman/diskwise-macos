import type { Metadata } from "next";
import { Montserrat } from "next/font/google";
import { Suspense } from "react";
import "./globals.css";
import { GoogleAnalytics } from "@/components/GoogleAnalytics";
import { Header } from "@/components/Header";
import { Footer } from "@/components/Footer";
import { BRAND_NAME, BRAND_TAGLINE, SITE_URL } from "@/lib/brand";

const montserrat = Montserrat({
  subsets: ["latin"],
  weight: ["400", "500", "600", "700"],
  variable: "--font-montserrat",
  display: "swap",
});

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: BRAND_NAME,
  description: `${BRAND_TAGLINE}. Scan storage, score system health, find duplicates, clean caches safely, and get on-device AI insights.`,
  icons: {
    icon: [
      { url: "/app-icon.png", type: "image/png", sizes: "512x512" },
      { url: "/app-icon.png", type: "image/png", sizes: "192x192" },
    ],
    apple: "/app-icon.png",
    shortcut: "/app-icon.png",
  },
  openGraph: {
    type: "website",
    siteName: BRAND_NAME,
    title: BRAND_NAME,
    description: `${BRAND_TAGLINE}. Scan storage, score system health, find duplicates, clean caches safely, and get on-device AI insights.`,
    url: SITE_URL,
    images: [
      {
        url: "/app-icon.png",
        width: 1024,
        height: 1024,
        alt: `${BRAND_NAME} app icon`,
      },
    ],
  },
  twitter: {
    card: "summary",
    title: BRAND_NAME,
    description: `${BRAND_TAGLINE}. Scan storage, score system health, find duplicates, clean caches safely, and get on-device AI insights.`,
    images: ["/app-icon.png"],
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className={`dark ${montserrat.variable}`}>
      <body className={`${montserrat.className} bg-[var(--background)] text-slate-100 antialiased`}>
        <Suspense fallback={null}>
          <GoogleAnalytics />
        </Suspense>
        <Header />
        <main>{children}</main>
        <Footer />
      </body>
    </html>
  );
}
