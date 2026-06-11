import type { Metadata } from "next";
import Link from "next/link";
import { Suspense } from "react";
import { VersionHistory } from "@/components/VersionHistory";
import { BRAND_NAME } from "@/lib/brand";

export const metadata: Metadata = {
  title: `Version History · ${BRAND_NAME}`,
  description:
    "Browse every DiskWise release, read release notes, and download any DMG version.",
};

export default function VersionsPage() {
  return (
    <>
      <div className="mx-auto max-w-7xl px-4 pt-8 sm:px-6 sm:pt-10 lg:pt-12">
        <Link href="/" className="text-sm font-medium text-brand-blue hover:underline">
          ← Back to home
        </Link>
      </div>
      <Suspense
        fallback={
          <section className="mx-auto max-w-7xl px-4 py-8 sm:px-6 sm:py-10">
            <div className="mt-6 space-y-4" aria-busy="true" aria-label="Loading releases">
              {[0, 1, 2].map((key) => (
                <div key={key} className="card p-6">
                  <div className="h-6 w-24 animate-pulse rounded bg-slate-700" />
                  <div className="mt-3 h-4 w-2/3 animate-pulse rounded bg-slate-800" />
                </div>
              ))}
            </div>
          </section>
        }
      >
        <VersionHistory />
      </Suspense>
    </>
  );
}
