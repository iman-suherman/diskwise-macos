import Image from "next/image";
import { BRAND_NAME } from "@/lib/brand";

const previews = [
  {
    image: "/app-screenshot-overview.png",
    width: 913,
    height: 542,
    alt: `${BRAND_NAME} storage overview with capacity cards, donut chart, and storage breakdown by file type`,
    title: "Understand where your space goes",
    headline: "Capacity, savings, and storage by type — all in one Overview.",
    description:
      "After a scan completes, the Overview shows total, used, and free capacity alongside indexed file counts and potential savings. A donut chart breaks usage into Development, Other, Backups, Documents, Media, Caches, and more — each with size, percentage, and file count so hotspots are obvious before you clean anything.",
    imageFirst: true,
    large: true,
  },
  {
    image: "/app-screenshot-insights.png",
    width: 920,
    height: 511,
    alt: `${BRAND_NAME} showing biggest space consumers, storage intelligence savings, and safe cleanup recommendations`,
    title: "Act on safe cleanup suggestions",
    headline: "Ranked hotspots, reclaimable space, and actions you control.",
    description:
      "DiskWise ranks your biggest folders — Library, Xcode, Application Support, and more — so you know what to inspect first. Storage Intelligence totals reclaimable space across caches, old DMGs, temporary exports, and stale files, then turns findings into recommended actions with plain-language guidance. Review each suggestion and move ahead only when it makes sense.",
    imageFirst: false,
    large: true,
  },
  {
    image: "/app-screenshot-chat.png",
    width: 930,
    height: 534,
    alt: `${BRAND_NAME} Ask DiskWise AI chat answering what is consuming the most disk space`,
    title: "Ask DiskWise anything",
    headline: "AI chat powered by your scan data — on your Mac.",
    description:
      "Open Ask DiskWise and get plain-language answers about your storage. Ask what is consuming the most space, which categories dominate, or where to start cleaning — responses are grounded in your latest scan, not generic advice. No cloud upload required; insights stay on-device.",
    imageFirst: true,
    large: true,
  },
] as const;

function imageWrapperClass(large: boolean) {
  return large
    ? "relative mx-auto w-full max-w-3xl sm:max-w-4xl lg:mx-0 lg:max-w-none"
    : "relative mx-auto w-full max-w-2xl lg:mx-0 lg:max-w-none";
}

export function AppPreview() {
  return (
    <section id="preview" className="mx-auto max-w-7xl px-4 py-6 sm:px-6 sm:py-8 md:py-10">
      <div className="mx-auto max-w-3xl text-center">
        <p className="text-sm font-semibold uppercase tracking-wide text-brand-blue">
          Native macOS app
        </p>
        <h2 className="mt-2 text-2xl font-bold text-slate-50 sm:text-3xl md:text-4xl">
          From first scan to confident cleanup.
        </h2>
        <p className="mt-3 text-base leading-7 text-slate-400">
          {BRAND_NAME} keeps scanning, analysis, safe cleanup suggestions, and AI chat in one
          focused SwiftUI workspace — on your Mac, with your data.
        </p>
      </div>

      <div className="mt-10 space-y-12 lg:space-y-20">
        {previews.map((preview) => (
          <article
            key={preview.image}
            className={`grid items-center gap-8 ${
              preview.large ? "lg:grid-cols-[1.15fr_0.85fr] lg:gap-12" : "lg:grid-cols-2 lg:gap-10"
            } ${preview.imageFirst ? "" : "lg:[&>div:first-child]:order-2 lg:[&>div:last-child]:order-1"}`}
          >
            <div className={imageWrapperClass(preview.large)}>
              <div className="absolute -inset-6 rounded-full bg-gradient-to-br from-brand-blue/10 via-brand-purple/5 to-transparent blur-3xl" />
              <div className="relative rounded-[1.35rem] sm:rounded-[1.5rem]">
                <div className="relative overflow-hidden rounded-xl shadow-[0_4px_14px_rgba(0,0,0,0.55),0_20px_48px_rgba(0,0,0,0.5),0_40px_80px_rgba(0,0,0,0.4)] sm:rounded-2xl">
                  <Image
                    src={preview.image}
                    alt={preview.alt}
                    width={preview.width}
                    height={preview.height}
                    unoptimized
                    sizes={preview.large ? "(max-width: 1024px) 100vw, 42rem" : "(max-width: 1024px) 90vw, 32rem"}
                    className="relative block h-auto w-full object-contain"
                  />
                  <div
                    aria-hidden
                    className="pointer-events-none absolute inset-0 rounded-xl bg-[linear-gradient(to_bottom,rgba(0,0,0,0.18)_0%,transparent_28%,transparent_72%,rgba(0,0,0,0.32)_100%)] sm:rounded-2xl"
                  />
                  <div
                    aria-hidden
                    className="pointer-events-none absolute inset-0 rounded-xl shadow-[inset_0_1px_0_rgba(255,255,255,0.07),inset_0_-20px_40px_rgba(0,0,0,0.22)] sm:rounded-2xl"
                  />
                </div>
              </div>
            </div>

            <div className={preview.imageFirst ? "lg:pl-2" : "lg:pr-2"}>
              <p className="text-sm font-semibold uppercase tracking-wide text-brand-blue">
                {preview.title}
              </p>
              <h3 className="mt-2 text-2xl font-bold text-slate-50 sm:mt-3 sm:text-3xl md:text-4xl">
                {preview.headline}
              </h3>
              <p className="mt-4 max-w-xl text-sm leading-6 text-slate-400 sm:text-base sm:leading-7">
                {preview.description}
              </p>
            </div>
          </article>
        ))}
      </div>
    </section>
  );
}
