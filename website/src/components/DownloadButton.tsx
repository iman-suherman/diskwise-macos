"use client";

import { toPublicDownloadUrl, type AppVersion } from "@/lib/registry";

type DownloadButtonProps = {
  latest: AppVersion | null;
  loading: boolean;
  className?: string;
  /** Defaults to "Download for Mac". Use a shorter label in narrow cards. */
  labelPrefix?: string;
};

export function DownloadButton({
  latest,
  loading,
  className = "btn-primary",
  labelPrefix = "Download for Mac",
}: DownloadButtonProps) {
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
      {labelPrefix} · v{latest.version}
    </a>
  );
}
