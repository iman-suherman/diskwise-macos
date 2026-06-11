"use client";

import { toPublicDownloadUrl, type AppVersion } from "@/lib/registry";

type DownloadButtonProps = {
  latest: AppVersion | null;
  loading: boolean;
  className?: string;
};

export function DownloadButton({ latest, loading, className = "btn-primary" }: DownloadButtonProps) {
  if (loading) {
    return (
      <button type="button" className={className} disabled aria-busy="true">
        Loading…
      </button>
    );
  }

  if (!latest?.version) {
    return null;
  }

  return (
    <a href={toPublicDownloadUrl(latest)} className={className}>
      Download v{latest.version}
    </a>
  );
}
