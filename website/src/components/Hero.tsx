"use client";

import Link from "next/link";
import { LocalReleaseDate } from "@/components/LocalReleaseDate";
import { ScanningHeroIcon } from "@/components/ScanningHeroIcon";
import { BRAND_NAME, BRAND_TAGLINE } from "@/lib/brand";
import { DownloadButton } from "@/components/DownloadButton";
import { useLatestVersion } from "@/hooks/useRegistry";
import {
  flattenReleaseNotes,
  formatBytes,
  publishedAtToIso,
} from "@/lib/registry";

export function Hero() {
  const { data: latest, loading } = useLatestVersion();
  const versionLabel = latest?.version;
  const releasedAtIso = publishedAtToIso(latest?.publishedAt);
  const highlights = flattenReleaseNotes(latest?.releaseNotes).slice(0, 3);

  return (
    <section id="home" className="mx-auto max-w-7xl px-4 py-10 sm:px-6 md:py-14 lg:py-20">
      <div className="grid gap-8 lg:grid-cols-2 lg:items-center lg:gap-10">
        <div>
          <span className="inline-flex rounded-full bg-brand-blue/15 px-3 py-1 text-xs font-semibold uppercase tracking-wide text-brand-blue sm:px-4 sm:py-1.5 sm:text-sm">
            {BRAND_TAGLINE}
          </span>
          <h1 className="mt-4 max-w-4xl text-balance text-3xl font-bold leading-[1.15] tracking-tight text-slate-50 sm:mt-6 sm:text-4xl md:text-5xl lg:text-[3.25rem] xl:text-6xl">
            Reclaim disk space with{" "}
            <span className="gradient-text">AI-powered storage insights.</span>
          </h1>
          <p className="mt-4 max-w-3xl text-base leading-7 text-slate-400 sm:mt-6 sm:text-lg sm:leading-8 md:text-xl md:leading-9">
            Scan volumes, find duplicate videos, get safe cleanup suggestions, and ask AI about your
            storage — all from a native macOS app built for privacy.
          </p>

          <div id="download" className="mt-6 flex flex-col gap-3 sm:mt-8">
            <div className="flex flex-col gap-3 sm:flex-row sm:flex-nowrap sm:items-center sm:gap-2 lg:gap-3">
              <DownloadButton
                latest={latest}
                loading={loading}
                className="btn-primary w-full shrink-0 whitespace-nowrap px-5 py-3 text-sm sm:w-auto sm:px-6 sm:py-3 lg:px-5"
              />
              <Link
                href="/versions"
                className="btn-secondary w-full shrink-0 whitespace-nowrap px-5 py-3 text-sm sm:w-auto sm:px-6 sm:py-3 lg:px-5"
              >
                View release history
              </Link>
              <Link
                href="/install"
                className="btn-secondary w-full shrink-0 whitespace-nowrap px-5 py-3 text-sm sm:w-auto sm:px-6 sm:py-3 lg:px-5"
              >
                Install guide
              </Link>
            </div>
            {releasedAtIso && (
              <LocalReleaseDate iso={releasedAtIso} className="text-base text-slate-500" />
            )}
          </div>

          <div className="mt-6 flex flex-wrap gap-x-6 gap-y-2 text-sm text-slate-500 sm:mt-8 sm:gap-x-8 sm:text-base">
            <span>On-device analysis</span>
            <span>Duplicate video detection</span>
            <span>Safe Trash workflow</span>
          </div>
        </div>

        <div className="relative mx-auto flex w-full max-w-md items-center justify-center overflow-visible lg:mx-0 lg:max-w-lg">
          <div
            aria-hidden
            className="absolute inset-0 scale-90 rounded-full bg-gradient-to-br from-brand-blue/35 via-brand-purple/20 to-brand-green/15 blur-3xl"
          />
          <ScanningHeroIcon priority className="relative w-full" />
        </div>
      </div>

      {loading && (
        <aside
          aria-label="Latest release"
          aria-busy="true"
          className="mt-8 border-t border-white/10 pt-8"
        >
          <p className="text-xs font-semibold uppercase tracking-wider text-brand-blue/80">
            Latest release
          </p>
          <div className="mt-3 h-5 w-3/4 max-w-md animate-pulse rounded bg-slate-700" />
          <div className="mt-2 h-4 w-1/2 max-w-xs animate-pulse rounded bg-slate-800" />
        </aside>
      )}

      {!loading && latest && (
        <aside aria-label="Latest release" className="mt-8 border-t border-white/10 pt-8">
          <p className="text-xs font-semibold uppercase tracking-wider text-brand-blue/80">
            Latest release
          </p>
          <p className="mt-3 text-base font-semibold leading-snug text-slate-100 sm:text-lg">
            {latest.summary ?? `${BRAND_NAME} ${versionLabel}`}
          </p>
          <p className="mt-2 text-sm text-slate-500">
            {formatBytes(latest.sizeBytes)} · macOS 14+ · Universal binary
          </p>
          {highlights.length > 0 && (
            <ul className="mt-5 space-y-2.5 text-sm leading-relaxed text-slate-400">
              {highlights.map((note) => (
                <li key={note} className="flex gap-2">
                  <span aria-hidden className="shrink-0 text-slate-600">
                    •
                  </span>
                  <span>{note}</span>
                </li>
              ))}
            </ul>
          )}
        </aside>
      )}
    </section>
  );
}
