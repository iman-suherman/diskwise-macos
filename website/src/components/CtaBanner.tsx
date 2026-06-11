"use client";

import Link from "next/link";
import { useLatestVersion } from "@/hooks/useRegistry";
import { DOWNLOAD_BASE_URL, toPublicDownloadUrl } from "@/lib/registry";

const FALLBACK_DOWNLOAD_URL = `${DOWNLOAD_BASE_URL.replace(/\/$/, "")}/latest.dmg`;

export function CtaBanner() {
  const { data: latest } = useLatestVersion();
  const downloadUrl = latest ? toPublicDownloadUrl(latest) : FALLBACK_DOWNLOAD_URL;

  return (
    <section className="mx-auto max-w-7xl px-4 pb-6 sm:px-6 sm:pb-8">
      <div className="rounded-2xl bg-gradient-to-r from-brand-blue via-[#005ecb] to-brand-blueDark px-5 py-6 text-white shadow-card ring-1 ring-white/10 sm:rounded-[2rem] sm:px-8 sm:py-8 md:px-10">
        <div className="flex flex-col gap-5 md:flex-row md:items-center md:justify-between">
          <div>
            <h2 className="text-xl font-bold sm:text-2xl md:text-3xl">
              Ready to understand what is using your disk?
            </h2>
            <p className="mt-3 max-w-2xl text-sm leading-7 text-blue-100 md:text-base">
              Download DiskWise for macOS, scan your volumes, and start reclaiming space with
              confidence.
            </p>
          </div>
          <div className="grid w-full gap-3 sm:w-auto sm:grid-cols-2">
            <a href={downloadUrl} className="btn-cta-primary">
              {latest ? `Download v${latest.version}` : "Download for macOS"}
            </a>
            <Link href="/versions" className="btn-cta-secondary">
              Browse versions
            </Link>
          </div>
        </div>
      </div>
    </section>
  );
}
