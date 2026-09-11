"use client";

import Image from "next/image";
import Link from "next/link";
import { AppStoreLink } from "@/components/AppStoreLink";
import { LocalReleaseDate } from "@/components/LocalReleaseDate";
import { DownloadButton } from "@/components/DownloadButton";
import { useLatestVersion } from "@/hooks/useRegistry";
import { publishedAtToIso, toPublicDownloadUrl } from "@/lib/registry";

const steps = [
  {
    title: "Download the DMG",
    description:
      "Get the latest DiskWise build, or pick a specific version from the release history page.",
    detail: "Save the `.dmg` file to your Downloads folder.",
  },
  {
    title: "Open the disk image",
    description: "Double-click the downloaded DMG to mount it in Finder.",
    detail: "macOS may verify the notarized build automatically.",
  },
  {
    title: "Drag to Applications",
    description: "Drag DiskWise.app into your Applications folder.",
    detail: "You can eject the disk image after copying the app.",
  },
  {
    title: "Launch DiskWise",
    description: "Open DiskWise from Applications or Spotlight.",
    detail: "On first launch, macOS may ask you to confirm opening a downloaded app.",
  },
  {
    title: "Grant permissions when prompted",
    description:
      "DiskWise may request Full Disk Access to scan volumes outside your home folder.",
    detail:
      "Open System Settings → Privacy & Security → Full Disk Access and enable DiskWise when ready.",
  },
  {
    title: "Run your first scan or health check",
    description:
      "Open Disk Analysis to scan a drive, or System Optimization for a health score and memory insights.",
    detail: "All analysis stays on your Mac — preview cleanup before anything moves to Trash.",
  },
];

export function InstallGuide() {
  const { data: latest, loading } = useLatestVersion();
  const versionLabel = latest?.version;
  const releasedAtIso = publishedAtToIso(latest?.publishedAt);
  const downloadUrl = latest ? toPublicDownloadUrl(latest) : null;
  const downloadLabel = versionLabel ? `Download v${versionLabel}` : "Download";

  return (
    <article className="mx-auto max-w-3xl px-4 py-8 sm:px-6 sm:py-10 lg:py-12">
      <Link href="/" className="text-sm font-medium text-brand-blue hover:underline">
        ← Back to home
      </Link>

      <p className="mt-6 text-sm font-semibold uppercase tracking-wide text-brand-blue">
        Get DiskWise
      </p>
      <h1 className="mt-3 text-3xl font-bold text-slate-50 md:text-4xl">
        Download for Mac, or get it on the App Store
      </h1>
      <p className="mt-4 text-base leading-7 text-slate-400">
        DiskWise for macOS is a notarized DMG. DiskWise for iPhone and iPad is on the App Store
        and helps you clean Photos clutter on-device.
      </p>

      <div className="mt-8 grid gap-4 sm:grid-cols-2">
        <div className="card p-6">
          <p className="text-xs font-semibold uppercase tracking-wide text-slate-500">macOS</p>
          <h2 className="mt-2 text-lg font-semibold text-slate-100">Download the DMG</h2>
          <p className="mt-2 text-sm leading-6 text-slate-400">
            Universal binary for Apple Silicon and Intel. macOS 14 or later.
          </p>
          <div className="mt-4">
            <DownloadButton latest={latest} loading={loading} className="btn-primary w-full" />
          </div>
        </div>
        <div className="card p-6">
          <p className="text-xs font-semibold uppercase tracking-wide text-slate-500">
            iPhone &amp; iPad
          </p>
          <h2 className="mt-2 text-lg font-semibold text-slate-100">Get it on the App Store</h2>
          <p className="mt-2 text-sm leading-6 text-slate-400">
            Photos duplicates, screenshots, and large videos — preview, then Recently Deleted.
            iOS 17 or later.
          </p>
          <div className="mt-3">
            <AppStoreLink variant="badge" className="-ml-2.5" />
          </div>
        </div>
      </div>

      <h2 className="mt-12 text-2xl font-bold text-slate-50">Install DiskWise on macOS</h2>
      <p className="mt-3 text-base leading-7 text-slate-400">
        Follow these steps to download the DMG, drag DiskWise into Applications, and explore disk
        analysis, system health, and safe cleanup.
      </p>

      <div className="relative mt-8 overflow-hidden rounded-2xl border border-white/10 shadow-soft">
        <Image
          src="/screenshot-install-dmg.png"
          alt="DiskWise DMG installer window showing drag to Applications"
          width={1024}
          height={679}
          unoptimized
          className="block h-auto w-full"
        />
      </div>

      <div className="mt-8 flex flex-col gap-2">
        <div className="flex flex-wrap items-center gap-4">
          <Link href="/versions" className="btn-secondary">
            Browse all Mac versions
          </Link>
        </div>
        {releasedAtIso && (
          <LocalReleaseDate iso={releasedAtIso} className="text-sm text-slate-500" />
        )}
      </div>

      <ol className="mt-10 space-y-5">
        {steps.map((step, index) => (
          <li key={step.title} className="card p-6">
            <div className="flex gap-4">
              <span className="inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-brand-blue/15 text-sm font-bold text-brand-blue">
                {index + 1}
              </span>
              <div>
                <h2 className="text-lg font-semibold text-slate-100">{step.title}</h2>
                <p className="mt-2 text-sm leading-6 text-slate-400">{step.description}</p>
                <p className="mt-2 text-sm text-slate-500">{step.detail}</p>
                {index === 0 && !loading && downloadUrl && (
                  <a
                    href={downloadUrl}
                    className="mt-4 inline-flex text-sm font-semibold text-brand-blue hover:underline"
                  >
                    {downloadLabel} →
                  </a>
                )}
                {index === 0 && loading && (
                  <p className="mt-4 text-sm text-slate-500" aria-busy="true">
                    Loading latest release…
                  </p>
                )}
              </div>
            </div>
          </li>
        ))}
      </ol>

      <div className="card mt-8 p-6">
        <h2 className="text-lg font-semibold text-slate-100">System requirements</h2>
        <ul className="mt-3 space-y-2 text-sm leading-6 text-slate-400">
          <li>• Mac: macOS 14 (Sonoma) or later, Apple Silicon or Intel</li>
          <li>• iPhone &amp; iPad: iOS 17 or iPadOS 17 or later</li>
          <li>• Full Disk Access recommended for complete Mac volume scans</li>
          <li>• Photo Library access required for the iOS app (full access recommended)</li>
        </ul>
      </div>
    </article>
  );
}
