export const GA_MEASUREMENT_ID =
  process.env.NEXT_PUBLIC_GA_MEASUREMENT_ID?.trim() || "G-PTRL7GJ8CV";

declare global {
  interface Window {
    dataLayer: unknown[];
    gtag: (...args: unknown[]) => void;
  }
}

export function gtag(...args: unknown[]) {
  if (typeof window === "undefined" || typeof window.gtag !== "function") return;
  window.gtag(...args);
}

export function trackPageView(path: string) {
  gtag("config", GA_MEASUREMENT_ID, {
    page_path: path,
  });
}

export function isDownloadUrl(url: string): boolean {
  try {
    const parsed = new URL(url);
    const path = parsed.pathname.toLowerCase();
    return (
      path.endsWith(".dmg") ||
      path.endsWith(".zip") ||
      path.includes("/downloads/") ||
      parsed.hostname.includes("diskwise-download")
    );
  } catch {
    return false;
  }
}

export function trackFileDownload({
  url,
  fileName,
  linkText,
}: {
  url: string;
  fileName: string;
  linkText?: string;
}) {
  gtag("event", "file_download", {
    file_name: fileName,
    link_url: url,
    link_text: linkText,
    download_source: "website",
  });
}

export function trackOutboundLink({ url, linkText }: { url: string; linkText?: string }) {
  gtag("event", "click", {
    event_category: "outbound",
    event_label: url,
    link_url: url,
    link_text: linkText,
    outbound: true,
  });
}
