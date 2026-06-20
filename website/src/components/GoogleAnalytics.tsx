"use client";

import Script from "next/script";
import { usePathname, useSearchParams } from "next/navigation";
import { useEffect } from "react";
import {
  GA_MEASUREMENT_ID,
  isDownloadUrl,
  trackFileDownload,
  trackOutboundLink,
  trackPageView,
} from "@/lib/analytics";

function GoogleAnalyticsTracker() {
  const pathname = usePathname();
  const searchParams = useSearchParams();

  useEffect(() => {
    const query = searchParams.toString();
    trackPageView(query ? `${pathname}?${query}` : pathname);
  }, [pathname, searchParams]);

  useEffect(() => {
    function handleClick(event: MouseEvent) {
      if (event.defaultPrevented || event.button !== 0) return;
      if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;

      const anchor = (event.target as HTMLElement | null)?.closest("a");
      if (!anchor?.href) return;

      const url = anchor.href;
      const linkText = anchor.textContent?.trim() || undefined;

      if (isDownloadUrl(url)) {
        let fileName = "download";
        try {
          fileName = decodeURIComponent(new URL(url).pathname.split("/").pop() || fileName);
        } catch {
          /* ignore */
        }
        trackFileDownload({ url, fileName, linkText });
        return;
      }

      try {
        const linkHost = new URL(url).hostname;
        const siteHost = window.location.hostname;
        if (linkHost && linkHost !== siteHost && anchor.target === "_blank") {
          trackOutboundLink({ url, linkText });
        }
      } catch {
        /* ignore */
      }
    }

    document.addEventListener("click", handleClick);
    return () => document.removeEventListener("click", handleClick);
  }, []);

  return null;
}

export function GoogleAnalytics() {
  return (
    <>
      <Script
        src={`https://www.googletagmanager.com/gtag/js?id=${GA_MEASUREMENT_ID}`}
        strategy="afterInteractive"
      />
      <Script id="google-analytics" strategy="afterInteractive">
        {`
          window.dataLayer = window.dataLayer || [];
          function gtag(){dataLayer.push(arguments);}
          gtag('js', new Date());
          gtag('config', '${GA_MEASUREMENT_ID}', { send_page_view: false });
        `}
      </Script>
      <GoogleAnalyticsTracker />
    </>
  );
}
